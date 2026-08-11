#!/usr/bin/env python3
"""零引用守卫（docs/屎山消灭计划.md 批次 A 之 2，白名单制）。

候选定义：
- game/ 下的 .tscn 文件：其 res:// 路径与文件名在仓库其他文本文件中零出现；
- game/ 下 .gd 的 ``class_name X``：标识符 X 在定义文件之外零出现。

两个清单：
- zero_reference_whitelist.json：动态加载、编辑器工具、手工预览等无静态引用的
  合法项，逐项记用途（purpose）、消费者（consumer）、负责人（owner）。
- zero_reference_baseline.json：存量候选（批次 C 逐项确认删除或转入白名单，
  只减不增）。

CI 判定（--check）：候选不在白名单也不在基线 = 新增未解释候选 = 失败。

模式：
  --check            CI 判定（默认）。
  --write-baseline   把当前白名单外候选写入基线（初始化/清理后收缩）。
  --list             列出全部当前候选及其归属。
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from guard_common import GAME_ROOT, GUARDS_ROOT, REPO_ROOT, rel  # noqa: E402

BASELINE_FILE = GUARDS_ROOT / "zero_reference_baseline.json"
WHITELIST_FILE = GUARDS_ROOT / "zero_reference_whitelist.json"

CORPUS_SUFFIXES = {".gd", ".tscn", ".tres", ".sh", ".cfg", ".json", ".godot", ".import"}
CLASS_NAME_RE = re.compile(r"^\s*class_name\s+([A-Za-z_]\w*)", re.MULTILINE)


def corpus_files() -> list[Path]:
    files = []
    for root in (GAME_ROOT, REPO_ROOT / "tools"):
        for path in root.rglob("*"):
            if not path.is_file() or path.suffix not in CORPUS_SUFFIXES:
                continue
            if path.is_relative_to(GUARDS_ROOT):
                continue  # 守卫自身的基线/清单会"引用"所有候选名，必须排除
            parts = path.parts
            if ".godot" in parts or "addons" in parts:
                continue
            files.append(path)
    return files


def collect_candidates() -> dict[str, dict]:
    """返回 {候选 id: 描述}。id 形如 'tscn:game/x/y.tscn' 或 'class:Name'。"""
    texts: dict[str, str] = {}
    for path in corpus_files():
        try:
            texts[rel(path)] = path.read_text(encoding="utf-8")
        except UnicodeDecodeError:
            continue

    class_defs: dict[str, str] = {}
    for rel_path, text in texts.items():
        if not rel_path.endswith(".gd") or not rel_path.startswith("game/"):
            continue
        for match in CLASS_NAME_RE.finditer(text):
            class_defs.setdefault(match.group(1), rel_path)

    tscn_paths = [p for p in texts if p.endswith(".tscn") and p.startswith("game/")]

    # 一遍扫描：把所有类名与 tscn 文件名并入一个交替正则，统计出现次数。
    tokens = list(class_defs.keys()) + [Path(p).name for p in tscn_paths]
    if not tokens:
        return {}
    # 注意：不能把 / 放进后行断言——res://path/Foo.tscn 是最常见的引用形式。
    token_re = re.compile(
        r"(?<!\w)(" + "|".join(re.escape(t) for t in sorted(set(tokens), key=len, reverse=True)) + r")(?!\w)"
    )
    hits: dict[str, set[str]] = {}
    for rel_path, text in texts.items():
        for match in token_re.finditer(text):
            hits.setdefault(match.group(1), set()).add(rel_path)

    candidates: dict[str, dict] = {}
    for name, def_path in sorted(class_defs.items()):
        refs = hits.get(name, set()) - {def_path}
        if not refs:
            candidates[f"class:{name}"] = {"file": def_path}
    for tscn in sorted(tscn_paths):
        refs = hits.get(Path(tscn).name, set()) - {tscn, tscn + ".import"}
        refs = {r for r in refs if not r.startswith(tscn)}
        if not refs:
            candidates[f"tscn:{tscn}"] = {"file": tscn}
    return candidates


def load_ids(file: Path) -> set[str]:
    if not file.exists():
        return set()
    data = json.loads(file.read_text(encoding="utf-8"))
    return {entry["id"] for entry in data.get("entries", [])}


def cmd_check() -> int:
    candidates = collect_candidates()
    known = load_ids(BASELINE_FILE) | load_ids(WHITELIST_FILE)
    new = sorted(set(candidates) - known)
    if new:
        print("零引用守卫失败：出现白名单/基线外的新候选——")
        for cand in new:
            print(f"  {cand}  ({candidates[cand]['file']})")
        print(
            "\n处理方式：补上静态引用；确属动态加载/工具/预览则加入"
            " zero_reference_whitelist.json 并写明用途、消费者、负责人。"
        )
        return 1
    resolved = sorted(known - set(candidates) - load_ids(WHITELIST_FILE))
    if resolved:
        print(f"零引用守卫通过；{len(resolved)} 个基线候选已消失，可用 --write-baseline 收缩基线。")
    else:
        print("零引用守卫通过。")
    return 0


def cmd_write_baseline() -> int:
    candidates = collect_candidates()
    whitelist = load_ids(WHITELIST_FILE)
    entries = [
        {"id": cand, "file": info["file"]}
        for cand, info in sorted(candidates.items())
        if cand not in whitelist
    ]
    BASELINE_FILE.write_text(
        json.dumps({"version": 1, "entries": entries}, ensure_ascii=False, indent=1)
        + "\n",
        encoding="utf-8",
    )
    print(f"基线已写入 {rel(BASELINE_FILE)}：{len(entries)} 个存量候选。")
    return 0


def cmd_list() -> int:
    candidates = collect_candidates()
    baseline = load_ids(BASELINE_FILE)
    whitelist = load_ids(WHITELIST_FILE)
    for cand, info in sorted(candidates.items()):
        tag = "白名单" if cand in whitelist else ("基线存量" if cand in baseline else "新增!")
        print(f"  [{tag}] {cand}  ({info['file']})")
    print(f"共 {len(candidates)} 个候选。")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    group = parser.add_mutually_exclusive_group()
    group.add_argument("--check", action="store_true")
    group.add_argument("--write-baseline", action="store_true")
    group.add_argument("--list", action="store_true")
    args = parser.parse_args()
    if args.write_baseline:
        return cmd_write_baseline()
    if args.list:
        return cmd_list()
    return cmd_check()


if __name__ == "__main__":
    raise SystemExit(main())
