# -*- coding: utf-8 -*-
"""
端到端校验：三国穿越 reskin + backstory 接入是否真的打通。
检查四件事：
  1) resident_catalog.json 合法、16 个居民、每人 backstory 非空且在合理长度；
  2) 8 个 GD 校验/重建/渲染关卡都放行 backstory（不会被剥离或拒绝）；
  3) 镇子公共常识(lore)已写入穿越来历共识；
  4) 之前补丁引入的重复 var 已清除。
"""
import json
import os

BASE = r"D:\download\my_ai_town-main"
CAT = os.path.join(BASE, "game/world/data/town/resident_catalog.json")
LORE = os.path.join(BASE, "game/prompts/background/10_town_common_knowledge.md")

problems = []
checks_ok = []


# ---------- 1. 目录 JSON + backstory ----------
try:
    cat = json.load(open(CAT, encoding="utf-8"))
    checks_ok.append("resident_catalog.json: 合法 JSON")
except Exception as e:
    problems.append("resident_catalog.json 非法 JSON: %s" % e)
    cat = None

if cat:
    res = cat.get("residents", [])
    if len(res) != 16:
        problems.append("居民数量 = %d（应为 16）" % len(res))
    else:
        checks_ok.append("居民数量 = 16")
    bs_ok = 0
    for r in res:
        rid = r.get("residentId")
        attrs = r.get("attributes", {})
        bs = attrs.get("backstory")
        if not isinstance(bs, str) or not bs.strip():
            problems.append("%s: backstory 缺失/空" % rid)
            continue
        if not (20 <= len(bs) <= 200):
            problems.append("%s: backstory 长度异常 (%d)" % (rid, len(bs)))
            continue
        bs_ok += 1
    if bs_ok == len(res) and res:
        checks_ok.append("全部 %d 个居民 backstory 非空且长度合理" % bs_ok)


# ---------- 2. 8 个 GD 关卡的 white-list / 渲染 ----------
gate_expect = {
    "game/agent/contract/AgentContractIdentity.gd": [
        '"backstory",',
        "backstory 不能为空字符串",
        '"life_events",',
    ],
    "game/world/runtime/TownWorldRuntime.gd": [
        '"backstory",',
        '"backstory": String(',
        '"life_events",',
        '"life_events":',
    ],
    "game/world/runtime/TownWorldOpeningConfig.gd": ['"backstory",', '"life_events",'],
    "game/world/runtime/persistence/TownWorldRestorePeople.gd": ['"backstory",', '"life_events",'],
    "game/world/presentation/session/TownNewGameOpeningCompiler.gd": ['"backstory",', '"life_events",'],
    "game/world/presentation/session/TownResidentCatalog.gd": [
        '"backstory",',
        "legacy_without_backstory",
        "not _has_exact_fields(attributes, legacy_without_backstory)",
        '"life_events",',
        "legacy_without_life_events",
        "not _has_exact_fields(attributes, legacy_without_life_events)",
    ],
    "game/agent/prompt/AgentPromptCompiler.gd": ["前世记忆（三国）", "前世人生大事（三国）"],
    "game/agent/memory/MemoryOrganizer.gd": ["前世记忆（三国）", "前世人生大事（三国）"],
}
for rel, subs in gate_expect.items():
    p = os.path.join(BASE, rel)
    txt = open(p, encoding="utf-8").read()
    for s in subs:
        if s in txt:
            checks_ok.append("%s: 含 '%s'" % (rel, s))
        else:
            problems.append("%s: 缺 '%s'" % (rel, s))


# ---------- 3. lore 穿越共识 ----------
lore = open(LORE, encoding="utf-8").read()
for token in ["来历", "前身", "搬"]:
    if token in lore:
        checks_ok.append("lore: 含 '%s'" % token)
    else:
        problems.append("lore: 缺 '%s'" % token)


# ---------- 4. 残留重复 var 检查 ----------
trc = open(
    os.path.join(BASE, "game/world/presentation/session/TownResidentCatalog.gd"),
    encoding="utf-8",
).read()
if ("var \tvar" in trc) or ("var\tvar" in trc):
    problems.append("TownResidentCatalog.gd: 仍有重复 'var var'")
else:
    checks_ok.append("TownResidentCatalog.gd: 无重复 'var var'")


# ---------- 5. tk_timeline.json 结构校验 ----------
TL = os.path.join(BASE, "game/world/data/town/tk_timeline.json")
try:
    tl = json.load(open(TL, encoding="utf-8"))
    checks_ok.append("tk_timeline.json: 合法 JSON")
except Exception as e:
    problems.append("tk_timeline.json 非法 JSON: %s" % e)
    tl = None
if tl is not None:
    if tl.get("publisherId") != "tk_chronicle":
        problems.append("tk_timeline.json: publisherId 不是 'tk_chronicle'")
    events = tl.get("events", [])
    if not isinstance(events, list) or len(events) == 0:
        problems.append("tk_timeline.json: events 缺失/为空")
    else:
        req_keys = ["eventId", "gameDay", "era", "title", "summary", "bulletinText"]
        seen_ids = set()
        bad = 0
        for ev in events:
            if not isinstance(ev, dict):
                bad += 1
                continue
            missing = [k for k in req_keys if k not in ev]
            if missing:
                problems.append("tk_timeline.json: 事件缺键 %s" % missing)
                bad += 1
                continue
            if not (isinstance(ev["gameDay"], int) and ev["gameDay"] > 0):
                problems.append("tk_timeline.json: gameDay 非正整数 (%r)" % ev.get("gameDay"))
                bad += 1
                continue
            eid = ev["eventId"]
            if not (isinstance(eid, str) and eid.startswith("tk_")):
                problems.append("tk_timeline.json: eventId 未以 tk_ 前缀 (%r)" % eid)
                bad += 1
                continue
            if eid in seen_ids:
                problems.append("tk_timeline.json: eventId 重复 (%s)" % eid)
                bad += 1
                continue
            seen_ids.add(eid)
        if bad == 0:
            checks_ok.append("tk_timeline.json: %d 个事件全部结构合法且 eventId 唯一" % len(events))


# ---------- 6. resident_catalog life_events 校验 ----------
if cat is not None:
    le_ok = 0
    for r in res:
        rid = r.get("residentId")
        le = r.get("attributes", {}).get("life_events")
        if not isinstance(le, list) or not (3 <= len(le) <= 5):
            problems.append("%s: life_events 缺失或长度不在 3–5 (%r)" % (rid, len(le) if isinstance(le, list) else type(le).__name__))
            continue
        item_bad = False
        for it in le:
            if not isinstance(it, dict):
                item_bad = True
                break
            if not all(k in it for k in ["era", "title", "summary", "trigger"]):
                item_bad = True
                break
        if item_bad:
            problems.append("%s: life_events 子项缺 era/title/summary/trigger" % rid)
            continue
        le_ok += 1
    if le_ok == len(res) and res:
        checks_ok.append("全部 %d 个居民 life_events 合法（3–5 条且字段完整）" % le_ok)


# ---------- 报告 ----------
print("=" * 60)
print("通过检查点:", len(checks_ok))
for c in checks_ok:
    print("  [OK]", c)
print("\n问题:", len(problems))
for p in problems:
    print("  [X]", p)
print("\n结果:", "PASS ✅" if not problems else "FAIL ❌")
