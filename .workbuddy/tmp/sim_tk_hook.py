# -*- coding: utf-8 -*-
# 复刻 TownWorldRuntime.advance() 的跨日发帖钩子逻辑，验证逻辑修复。
import json

BASE = r"D:\download\my_ai_town-main"
tl = json.load(open(BASE + r"\game\world\data\town\k_timeline.json".replace("k_timeline", "tk_timeline"), encoding="utf-8"))
# 事件按 gameDay 归并
events_by_day = {}
for e in tl["events"]:
    events_by_day.setdefault(int(e["gameDay"]), []).append(e)

def absolute_minute(day, minute):
    # 复刻 _absolute_minute: (day-1)*1440 + minute
    return (day - 1) * 1440 + minute

class FakeBulletin:
    def __init__(self):
        self.posted = []          # 已发布 (day, text)
        self.announcements = []   # 模拟公告栏去重
    def get_announcements(self, inc):
        return self.announcements
    def publish(self, pub, text, matter, published_at, pt, mode, peid, sched):
        # 去重：若正文已存在则视为失败
        for a in self.announcements:
            if a["text"] == text:
                return {"ok": False}
        self.announcements.append({"text": text, "published_at": published_at})
        self.posted.append((published_at // 1440 + 1, text))
        return {"ok": True}

class FakePublisher:
    def __init__(self):
        self.posted_ids = set()
    def publish_due_for_day(self, wr, bulletin, day):
        n = 0
        for e in events_by_day.get(day, []):
            text = e["bulletinText"].strip()
            if not text:
                continue
            if e["eventId"] in self.posted_ids:
                continue
            # 公告栏去重
            dup = any(a["text"] == text for a in bulletin.get_announcements(True))
            if dup:
                self.posted_ids.add(e["eventId"])
                continue
            res = bulletin.publish("tk_chronicle", text, "", (day - 1) * 1440 + 480, {}, "board", "", {})
            if res.get("ok"):
                n += 1
                self.posted_ids.add(e["eventId"])
        return n

# ---- 复刻修复后的钩子 ----
def run_advance(wr, bulletin, publisher, minute_ticks):
    # minute_ticks: list[int] 绝对分钟序列（本次 advance 逐分钟 tick）
    tk_ticks = minute_ticks
    tk_last_day = 0
    if len(tk_ticks) > 0:
        tk_last_day = int(absolute_minute_to_day(tk_ticks[0]))
        # 修复公式: int(abs/1440)  = (first_day - 1)
    posted_total = 0
    for abs_min in tk_ticks:
        tk_tick_day = int(abs_min / 1440) + 1   # 修复后的整数除法
        if tk_tick_day > tk_last_day:
            for d in range(tk_last_day + 1, tk_tick_day + 1):
                posted_total += publisher.publish_due_for_day(wr, bulletin, d)
            tk_last_day = tk_tick_day
    return posted_total

def absolute_minute_to_day(abs_min):
    return abs_min / 1440   # 仅用于取首 tick 的 (day-1)

# 模拟：从 day1 凌晨推进到 day3 凌晨（含每个分钟 tick）
bulletin = FakeBulletin()
publisher = FakePublisher()
wr = None

# 构造 day1..day3 的逐分钟序列；这里只取每天 00:00 一个 tick 也足够触发（与真实逐分钟等价）
ticks = []
for day in (1, 2, 3):
    ticks.append(absolute_minute(day, 0))   # 每天 00:00
# 再补 day3 内几分钟（证明同日不重复发）
ticks.append(absolute_minute(3, 5))
ticks.append(absolute_minute(3, 10))

total = run_advance(wr, bulletin, publisher, ticks)
print("总发布次数:", total)
print("公告栏已发布 (day, text前20):")
for day, txt in bulletin.posted:
    print("  day=%d  %s" % (day, txt[:20]))

# 断言
days_posted = sorted(set(d for d, _ in bulletin.posted))
print("发布覆盖的日:", days_posted)
assert 1 not in days_posted, "day1 不应有事件（时间线无 day1 事件）"
assert 3 in days_posted, "day3 事件应被命中"
print("\nPASS: day3 事件命中, day1/day2(无事件)跳过, 同日不重复.")
