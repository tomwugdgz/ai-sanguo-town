# -*- coding: utf-8 -*-
"""为三国记忆 backstory 字段打通 attributes 数据管线。
所有改动均为往白名单/拷贝列表新增一个键（增量、不强制要求），
仅 TownResidentCatalog 的精确键校验额外加一个“无 backstory”兼容变体以不影响自定义居民。
"""
import re, sys, os

GAME = r"D:/download/my_ai_town-main/game"

FILES = {
    "AgentContractIdentity": os.path.join(GAME, "agent/contract/AgentContractIdentity.gd"),
    "OpeningCompiler": os.path.join(GAME, "world/presentation/session/TownNewGameOpeningCompiler.gd"),
    "OpeningConfig": os.path.join(GAME, "world/runtime/TownWorldOpeningConfig.gd"),
    "RestorePeople": os.path.join(GAME, "world/runtime/persistence/TownWorldRestorePeople.gd"),
    "Runtime": os.path.join(GAME, "world/runtime/TownWorldRuntime.gd"),
    "ResidentCatalog": os.path.join(GAME, "world/presentation/session/TownResidentCatalog.gd"),
    "PromptCompiler": os.path.join(GAME, "agent/prompt/AgentPromptCompiler.gd"),
    "MemoryOrganizer": os.path.join(GAME, "agent/memory/MemoryOrganizer.gd"),
}


def read(p):
    with open(p, encoding="utf-8") as f:
        return f.read()


def write(p, t):
    with open(p, "w", encoding="utf-8") as f:
        f.write(t)


def add_list_item_after(path, anchor, new_item):
    """在恰好等于 (若干空白)+anchor 的行后，插入一行（沿用该行缩进）new_item。"""
    text = read(path)
    pat = re.compile(r"^(\s*)" + re.escape(anchor) + r"$", re.M)
    m = pat.search(text)
    if not m:
        print("  [MISS] list anchor not found:", os.path.basename(path), repr(anchor))
        sys.exit(1)
    indent = m.group(1)
    text = text[: m.end()] + "\n" + indent + new_item + text[m.end():]
    write(path, text)
    print("  [OK] list +backstory ->", os.path.basename(path))


def append_after_line(path, anchor_substr, appended_block):
    """在首次出现含 anchor_substr 的行之后，追加 appended_block（可为多行，已含缩进）。"""
    text = read(path)
    idx = text.find(anchor_substr)
    if idx == -1:
        print("  [MISS] substr not found:", os.path.basename(path), repr(anchor_substr))
        sys.exit(1)
    # 找到该行末尾
    line_end = text.find("\n", idx)
    if line_end == -1:
        line_end = len(text)
    text = text[:line_end] + "\n" + appended_block + text[line_end:]
    write(path, text)
    print("  [OK] append ->", os.path.basename(path))


def replace_once(path, old, new):
    text = read(path)
    if old not in text:
        print("  [MISS] old not found:", os.path.basename(path), repr(old[:40]))
        sys.exit(1)
    if text.count(old) != 1:
        print("  [WARN] old not unique (%d):" % text.count(old), os.path.basename(path), repr(old[:40]))
    text = text.replace(old, new, 1)
    write(path, text)
    print("  [OK] replace ->", os.path.basename(path))


print("== 1) 白名单/拷贝列表：新增 backstory 键 ==")
# 这些 anchor 都是列表项（带逗号），且各自文件内唯一
add_list_item_after(FILES["AgentContractIdentity"], '"customInterests",', '"backstory",')
add_list_item_after(FILES["OpeningCompiler"], '"customInterests",', '"backstory",')
add_list_item_after(FILES["OpeningConfig"], '"customInterests",', '"backstory",')
add_list_item_after(FILES["RestorePeople"], '"customInterests",', '"backstory",')
add_list_item_after(FILES["Runtime"], '"customInterests",', '"backstory",')
add_list_item_after(FILES["ResidentCatalog"], '"customInterests",', '"backstory",')

print("== 2) AgentContractIdentity：backstory 非空兜底校验 ==")
append_after_line(
    FILES["AgentContractIdentity"],
    'AgentContract._require_non_empty_string(attributes, "speech", "me.attributes.speech", errors)',
    '\tif attributes.has("backstory") and String(attributes.get("backstory", "")).strip_edges().is_empty():\n\t\terrors.append("me.attributes.backstory 不能为空字符串")',
)

print("== 3) TownWorldRuntime：存盘也写入 backstory ==")
append_after_line(
    FILES["Runtime"],
    '"speech": String(attributes.get("speech", "")),',
    '\t\t"backstory": String(attributes.get("backstory", "")),',
)

print("== 4) TownResidentCatalog：加“无 backstory”兼容变体 ==")
# 4a) 在 legacy_without_interests.erase 之后插入 legacy_without_backstory 定义
append_after_line(
    FILES["ResidentCatalog"],
    'legacy_without_interests.erase("interests")',
    '\tvar legacy_without_backstory: Array[String] = (\n\t\tattribute_fields.duplicate()\n\t)\n\tlegacy_without_backstory.erase("backstory")',
)
# 4b) 在校验 if 条件里追加 and not _has_exact_fields(..., legacy_without_backstory)
replace_once(
    FILES["ResidentCatalog"],
    '\t\tand not _has_exact_fields(attributes, legacy_without_interests)\n\t):',
    '\t\tand not _has_exact_fields(attributes, legacy_without_interests)\n\t\tand not _has_exact_fields(attributes, legacy_without_backstory)\n\t):',
)

print("== 5) 渲染器：把 backstory 渲染进提示词 ==")
# 5a) PromptCompiler._render_initialization 说话方式之后
append_after_line(
    FILES["PromptCompiler"],
    '"说话方式：%s" % _safe(attributes.get("speech", "")),',
    '\t\t"前世记忆（三国）：%s" % _safe(attributes.get("backstory", "")),',
)
# 5b) PromptCompiler._render_oc_priority_context 模板 + 参数
replace_once(
    FILES["PromptCompiler"],
    "说话方式：%s\n",
    "说话方式：%s\n前世记忆（三国）：%s\n",
)
replace_once(
    FILES["PromptCompiler"],
    "relationship_text,\n\t]",
    'relationship_text,\n\t\t_safe(attributes.get("backstory", "")),\n\t]',
)
# 5c) MemoryOrganizer._render_initialization 说话方式之后
append_after_line(
    FILES["MemoryOrganizer"],
    '"说话方式：%s" % _safe(attributes.get("speech", "")),',
    '\t\t"前世记忆（三国）：%s" % _safe(attributes.get("backstory", "")),',
)

print("\nALL PATCHES APPLIED.")
