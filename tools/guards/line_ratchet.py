#!/usr/bin/env python3
"""行数棘轮守卫（docs/屎山消灭计划.md 批次 A 之 2）。

基线文件 line_ratchet.json 记录受控文件的行数上限，只降不升。
每拆一步用 --update 把基线下调到新行数；新增功能放进对应子模块，
或先拆出等量旧代码。

模式：
  --check            CI 判定：任一受控文件行数超基线即失败（默认模式）。
  --update           把所有受控文件的基线下调到当前行数（只降不升）。
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from guard_common import GUARDS_ROOT, REPO_ROOT, rel  # noqa: E402

BASELINE_FILE = GUARDS_ROOT / "line_ratchet.json"


def load_baseline() -> dict[str, int]:
    data = json.loads(BASELINE_FILE.read_text(encoding="utf-8"))
    return data["files"]


def count_lines(rel_path: str) -> int:
    return len((REPO_ROOT / rel_path).read_text(encoding="utf-8").splitlines())


def cmd_check() -> int:
    failures = []
    for rel_path, limit in load_baseline().items():
        lines = count_lines(rel_path)
        if lines > limit:
            failures.append((rel_path, lines, limit))
    if failures:
        print("行数棘轮失败（只降不升）：")
        for rel_path, lines, limit in failures:
            print(f"  {rel_path}: {lines} 行 > 基线 {limit} 行")
        return 1
    print("行数棘轮通过。")
    return 0


def cmd_update() -> int:
    baseline = load_baseline()
    changed = False
    for rel_path, limit in baseline.items():
        lines = count_lines(rel_path)
        if lines < limit:
            print(f"  {rel_path}: 基线 {limit} -> {lines}")
            baseline[rel_path] = lines
            changed = True
        elif lines > limit:
            print(f"  {rel_path}: {lines} 行超基线 {limit}，不允许上调，先解决超标。")
            return 1
    if changed:
        BASELINE_FILE.write_text(
            json.dumps({"version": 1, "files": baseline}, ensure_ascii=False, indent=1)
            + "\n",
            encoding="utf-8",
        )
        print(f"基线已更新：{rel(BASELINE_FILE)}")
    else:
        print("基线无变化。")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    group = parser.add_mutually_exclusive_group()
    group.add_argument("--check", action="store_true")
    group.add_argument("--update", action="store_true")
    args = parser.parse_args()
    return cmd_update() if args.update else cmd_check()


if __name__ == "__main__":
    raise SystemExit(main())
