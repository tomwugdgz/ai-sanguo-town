# -*- coding: utf-8 -*-
"""补齐 backstory 渲染 + 修正少数缩进错位的补丁（patch_backstory.py 因 4b 提前退出而漏跑的步骤）。"""
import re, sys, os

GAME = r"D:/download/my_ai_town-main/game"


def read(p):
    with open(p, encoding="utf-8") as f:
        return f.read()


def write(p, t):
    with open(p, "w", encoding="utf-8") as f:
        f.write(t)


def append_after_line(path, anchor_substr, block_lines):
    text = read(path)
    idx = text.find(anchor_substr)
    if idx == -1:
        print("MISS", os.path.basename(path), repr(anchor_substr))
        sys.exit(1)
    line_end = text.find("\n", idx)
    if line_end == -1:
        line_end = len(text)
    line_start = text.rfind("\n", 0, idx) + 1
    indent = ""
    for ch in text[line_start:idx]:
        if ch in " \t":
            indent += ch
        else:
            break
    ins = "\n".join(indent + ln for ln in block_lines)
    text = text[:line_end] + "\n" + ins + text[line_end:]
    write(path, text)
    print("OK insert", os.path.basename(path))


def replace_once(path, old, new):
    text = read(path)
    if old not in text:
        print("MISS old", os.path.basename(path), repr(old[:60]))
        sys.exit(1)
    text = text.replace(old, new, 1)
    write(path, text)
    print("OK replace", os.path.basename(path))


def reindent_regex(path, pat, repl):
    text = read(path)
    new, n = re.subn(pat, repl, text, count=1, flags=re.S)
    if n == 0:
        print("MISS regex", os.path.basename(path), repr(pat[:60]))
        sys.exit(1)
    write(path, new)
    print("OK regex", os.path.basename(path))


PC = os.path.join(GAME, "agent/prompt/AgentPromptCompiler.gd")
MO = os.path.join(GAME, "agent/memory/MemoryOrganizer.gd")
AC = os.path.join(GAME, "agent/contract/AgentContractIdentity.gd")
RC = os.path.join(GAME, "world/presentation/session/TownResidentCatalog.gd")

# A) AgentContractIdentity: 修正 backstory 兜底 if 的缩进为 2/3 制表
reindent_regex(
    AC,
    r'if attributes\.has\("backstory"\) and String\(attributes\.get\("backstory", ""\)\)\.strip_edges\(\)\.is_empty\(\):\n(\t*)errors\.append\("me\.attributes\.backstory 不能为空字符串"\)',
    '\t\tif attributes.has("backstory") and String(attributes.get("backstory", "")).strip_edges().is_empty():\n\t\t\terrors.append("me.attributes.backstory 不能为空字符串")',
)

# B) TownResidentCatalog: 修正 legacy_without_backstory 变量缩进
reindent_regex(
    RC,
    r'legacy_without_backstory: Array\[String\] = \((.*?)\)\s*legacy_without_backstory\.erase\("backstory"\)',
    '\tvar legacy_without_backstory: Array[String] = (\n\t\tattribute_fields.duplicate()\n\t)\n\tlegacy_without_backstory.erase("backstory")',
)

# C) TownResidentCatalog: 在校验条件里追加 legacy_without_backstory 兼容分支
reindent_regex(
    RC,
    r'and not _has_exact_fields\(attributes, legacy_without_interests\)\s*\):',
    'and not _has_exact_fields(attributes, legacy_without_interests)\n\t\tand not _has_exact_fields(attributes, legacy_without_backstory)\n\t):',
)

# D) PromptCompiler._render_initialization：说话方式后插入前世记忆
append_after_line(
    PC,
    '"说话方式：%s" % _safe(attributes.get("speech", "")),',
    ['"前世记忆（三国）：%s" % _safe(attributes.get("backstory", "")),'],
)

# E) PromptCompiler._render_oc_priority_context：模板插入前世记忆行
replace_once(PC, "说话方式：%s\n", "说话方式：%s\n前世记忆（三国）：%s\n")

# F) PromptCompiler._render_oc_priority_context：参数数组追加 backstory
replace_once(
    PC,
    "relationship_text,\n\t]",
    'relationship_text,\n\t\t_safe(attributes.get("backstory", "")),\n\t]',
)

# G) MemoryOrganizer._render_initialization：说话方式后插入前世记忆
append_after_line(
    MO,
    '"说话方式：%s" % _safe(attributes.get("speech", "")),',
    ['"前世记忆（三国）：%s" % _safe(attributes.get("backstory", "")),'],
)

print("DONE")
