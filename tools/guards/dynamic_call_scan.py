#!/usr/bin/env python3
"""统一动态调用扫描守卫（docs/屎山消灭计划.md 批次 A 之 2）。

覆盖的动态调用形式：
- ``obj.call("name", ...)`` / ``obj.call(&"name", ...)``（含换行参数）
- ``obj.callv("name", args)`` / ``obj.callv(&"name", args)``
- ``Callable(obj, "name")`` / ``Callable(obj, &"name")``
- 变量方法名：``obj.call(some_var, ...)`` / ``obj.callv(some_var, args)``

条目标识 = 文件路径 + 所在函数名 + 归一化调用内容（无行号，多重集计数）。

模式：
  --check              CI 判定：白名单外出现基线没有的新条目（或计数上升）即失败。
  --write-baseline     重写基线；已有基线时拒绝写入新增条目（防"顺手加回"），
                       初次生成或确需扩基线用 --allow-new 并在 PR 说明理由。
  --rebaseline-moves   纯搬运迁移通道：仅当归一化调用内容多重集与旧基线完全一致
                       （只有路径/函数名变化）才允许改写基线。
  --stats              打印分目录数量（仅展示，不判定）。
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from collections import Counter
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from guard_common import (  # noqa: E402
    GUARDS_ROOT,
    REPO_ROOT,
    production_gd_files,
    rel,
    strip_line_comment,
)

BASELINE_FILE = GUARDS_ROOT / "dynamic_call_baseline.json"
WHITELIST_FILE = GUARDS_ROOT / "dynamic_call_whitelist.json"

FUNC_RE = re.compile(r"^\s*(?:static\s+)?func\s+([A-Za-z_]\w*)")
CALL_RE = re.compile(r"\.(call|callv)\s*\(")
CALLABLE_RE = re.compile(r"\bCallable\s*\(")
STRING_ARG_RE = re.compile(r'^\s*&?"')


def extract_balanced(text: str, open_paren: int, limit: int = 4000) -> str | None:
    """从 open_paren（指向 '('）提取配平括号的调用参数段，含两侧括号。"""
    depth = 0
    quote = None
    i = open_paren
    end = min(len(text), open_paren + limit)
    while i < end:
        ch = text[i]
        if quote is not None:
            if ch == "\\":
                i += 2
                continue
            if ch == quote:
                quote = None
        elif ch in ('"', "'"):
            quote = ch
        elif ch == "(":
            depth += 1
        elif ch == ")":
            depth -= 1
            if depth == 0:
                return text[open_paren : i + 1]
        i += 1
    return None


def normalize(snippet: str) -> str:
    return re.sub(r"\s+", " ", snippet).strip()


def scan_file(path: Path) -> Counter:
    """返回 {(相对路径, 函数名, 归一化调用): 次数}。"""
    raw_lines = path.read_text(encoding="utf-8").splitlines()
    stripped = [strip_line_comment(line) for line in raw_lines]
    # 函数归属按行号确定；调用提取在去注释后的整文上做（支持换行参数）。
    func_of_line: list[str] = []
    current = "(module)"
    for line in stripped:
        match = FUNC_RE.match(line)
        if match:
            current = match.group(1)
        func_of_line.append(current)
    text = "\n".join(stripped)
    line_offsets = []
    offset = 0
    for line in stripped:
        line_offsets.append(offset)
        offset += len(line) + 1

    def line_of(pos: int) -> int:
        lo, hi = 0, len(line_offsets) - 1
        while lo < hi:
            mid = (lo + hi + 1) // 2
            if line_offsets[mid] <= pos:
                lo = mid
            else:
                hi = mid - 1
        return lo

    entries: Counter = Counter()
    rel_path = rel(path)

    for match in CALL_RE.finditer(text):
        open_paren = match.end() - 1
        args = extract_balanced(text, open_paren)
        if args is None:
            continue
        inner = args[1:-1].strip()
        kind = "string" if STRING_ARG_RE.match(inner) else "variable"
        snippet = normalize(f".{match.group(1)}{args}")
        func_name = func_of_line[line_of(match.start())]
        entries[(rel_path, func_name, f"{kind}:{snippet}")] += 1

    for match in CALLABLE_RE.finditer(text):
        open_paren = match.end() - 1
        args = extract_balanced(text, open_paren)
        if args is None:
            continue
        parts = args[1:-1].split(",", 1)
        if len(parts) < 2 or not STRING_ARG_RE.match(parts[1].strip()):
            continue  # Callable(fn) / Callable() 不是字符串方法名形式
        snippet = normalize(f"Callable{args}")
        func_name = func_of_line[line_of(match.start())]
        entries[(rel_path, func_name, f"string:{snippet}")] += 1

    return entries


def scan_all() -> Counter:
    total: Counter = Counter()
    for path in production_gd_files():
        total += scan_file(path)
    return total


def load_entries(file: Path) -> Counter:
    if not file.exists():
        return Counter()
    data = json.loads(file.read_text(encoding="utf-8"))
    counter: Counter = Counter()
    for item in data.get("entries", []):
        key = (item["path"], item["func"], item["call"])
        counter[key] += int(item.get("count", 1))
    return counter


def dump_entries(counter: Counter, file: Path, extra: dict | None = None) -> None:
    entries = [
        {"path": path, "func": func, "call": call, "count": count}
        for (path, func, call), count in sorted(counter.items())
    ]
    payload = {"version": 1}
    if extra:
        payload.update(extra)
    payload["entries"] = entries
    file.write_text(
        json.dumps(payload, ensure_ascii=False, indent=1) + "\n", encoding="utf-8"
    )


def dir_stats(counter: Counter) -> dict[str, int]:
    stats: Counter = Counter()
    for (path, _func, _call), count in counter.items():
        parts = Path(path).parts
        # 一级功能目录：game/<x>/ 或 game/world/<y>/
        if len(parts) >= 3 and parts[1] == "world":
            bucket = "/".join(parts[:3])
        else:
            bucket = "/".join(parts[:2])
        stats[bucket] += count
    return dict(sorted(stats.items()))


def cmd_check() -> int:
    current = scan_all()
    baseline = load_entries(BASELINE_FILE)
    whitelist = load_entries(WHITELIST_FILE)
    violations = []
    for key, count in current.items():
        if key in whitelist:
            continue
        allowed = baseline.get(key, 0)
        if count > allowed:
            violations.append((key, count, allowed))
    if violations:
        print("动态调用守卫失败：以下条目不在基线/白名单内（或计数上升）——")
        for (path, func, call), count, allowed in sorted(violations):
            print(f"  {path} :: {func} :: {call}  现 {count} / 基线 {allowed}")
        print(
            "\n处理方式：改为静态调用；确属必要动态调用则加入"
            " dynamic_call_whitelist.json 并写明理由；纯搬运用 --rebaseline-moves。"
        )
        return 1
    cleaned = {key: base - current.get(key, 0) for key, base in baseline.items() if base > current.get(key, 0)}
    if cleaned:
        print(f"动态调用守卫通过；{sum(cleaned.values())} 处已清理条目可用 --write-baseline 从基线剔除。")
    else:
        print("动态调用守卫通过。")
    return 0


def cmd_write_baseline(allow_new: bool) -> int:
    current = scan_all()
    if BASELINE_FILE.exists() and not allow_new:
        baseline = load_entries(BASELINE_FILE)
        whitelist = load_entries(WHITELIST_FILE)
        grown = [
            key
            for key, count in current.items()
            if key not in whitelist and count > baseline.get(key, 0)
        ]
        if grown:
            print("拒绝写入基线：存在基线外新增条目（条目只删不增）。新增：")
            for path, func, call in sorted(grown)[:20]:
                print(f"  {path} :: {func} :: {call}")
            print("确需扩基线请用 --allow-new 并在 PR 说明理由。")
            return 1
    dump_entries(current, BASELINE_FILE, {"stats": dir_stats(current)})
    print(f"基线已写入 {rel(BASELINE_FILE)}：{sum(current.values())} 处 / {len(current)} 个条目。")
    return 0


def cmd_rebaseline_moves() -> int:
    current = scan_all()
    baseline = load_entries(BASELINE_FILE)
    old_contents: Counter = Counter()
    for (_path, _func, call), count in baseline.items():
        old_contents[call] += count
    new_contents: Counter = Counter()
    for (_path, _func, call), count in current.items():
        new_contents[call] += count
    if old_contents != new_contents:
        added = new_contents - old_contents
        removed = old_contents - new_contents
        print("迁移校验失败：归一化调用内容多重集有变化，不是纯搬运。")
        for call, count in list(added.items())[:10]:
            print(f"  新增 x{count}: {call}")
        for call, count in list(removed.items())[:10]:
            print(f"  消失 x{count}: {call}")
        print("内容有增删的改动请走常规通道（--check 通过或 --write-baseline）。")
        return 1
    dump_entries(current, BASELINE_FILE, {"stats": dir_stats(current)})
    print("纯搬运迁移校验通过，基线路径/函数名已改写（调用内容多重集不变）。")
    return 0


def cmd_stats() -> int:
    current = scan_all()
    print(f"动态调用总计：{sum(current.values())} 处 / {len(current)} 个条目")
    for bucket, count in dir_stats(current).items():
        print(f"  {bucket}: {count}")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument("--check", action="store_true")
    group.add_argument("--write-baseline", action="store_true")
    group.add_argument("--rebaseline-moves", action="store_true")
    group.add_argument("--stats", action="store_true")
    parser.add_argument("--allow-new", action="store_true")
    args = parser.parse_args()
    if args.check:
        return cmd_check()
    if args.write_baseline:
        return cmd_write_baseline(args.allow_new)
    if args.rebaseline_moves:
        return cmd_rebaseline_moves()
    return cmd_stats()


if __name__ == "__main__":
    raise SystemExit(main())
