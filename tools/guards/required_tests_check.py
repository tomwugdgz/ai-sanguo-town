#!/usr/bin/env python3
"""正式套件防缩水守卫（docs/屎山消灭计划.md 铁律第 2 条、批次 A 之 3）。

required_tests.json 维护"必须存在的测试 ID 清单"：
- 清单中的每个测试 ID（res:// 路径）必须仍注册在
  game/tests/run_formal_release_story_suite.sh 的 checks 数组里，缺失即红；
- 注册的每个测试脚本文件必须存在于磁盘；
- 同一测试 ID 不允许重复注册（历史上的 2 处重复已去除，防止再犯）；
- 对清单中带 pinned_checks 的测试，runner 通过标记必须钉住 ``checks=<N>``
  （分测试最低断言数，铁律第 2 条 (b)）。

测试合并或删除时在 PR 里证明覆盖未减少，同步更新清单基线。
"""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from guard_common import GUARDS_ROOT, REPO_ROOT  # noqa: E402

REQUIRED_FILE = GUARDS_ROOT / "required_tests.json"
RUNNER_FILE = REPO_ROOT / "game/tests/run_formal_release_story_suite.sh"
ENTRY_RE = re.compile(r'^\s*"(res://(?:[^"\\]|\\.)+)"\s*$')


def parse_runner() -> list[tuple[str, str, int | None]]:
    """返回 [(测试 ID, 通过标记, 最低断言数或 None)]。条目形如 id|marker[|min]。"""
    entries = []
    in_array = False
    for line in RUNNER_FILE.read_text(encoding="utf-8").splitlines():
        if line.strip().startswith("checks=("):
            in_array = True
            continue
        if in_array and line.strip() == ")":
            break
        if in_array:
            match = ENTRY_RE.match(line)
            if match:
                fields = match.group(1).split("|")
                test_id = fields[0]
                marker = fields[1] if len(fields) > 1 else ""
                min_checks = int(fields[2]) if len(fields) > 2 else None
                entries.append((test_id, marker, min_checks))
    return entries


def main() -> int:
    required = json.loads(REQUIRED_FILE.read_text(encoding="utf-8"))["tests"]
    registered = parse_runner()
    registered_ids = [test_id for test_id, _marker, _min in registered]
    failures = []

    seen: set[str] = set()
    for test_id in registered_ids:
        if test_id in seen:
            failures.append(f"重复注册: {test_id}")
        seen.add(test_id)

    for test_id in registered_ids:
        disk = REPO_ROOT / "game" / test_id[len("res://") :]
        if not disk.exists():
            failures.append(f"注册的测试脚本不存在: {test_id}")

    required_ids = {item["id"] for item in required}
    for test_id in registered_ids:
        if test_id not in required_ids:
            failures.append(f"新注册测试未进清单（请同步 required_tests.json）: {test_id}")

    runner_min = {test_id: min_checks for test_id, _marker, min_checks in registered}
    for item in required:
        test_id = item["id"]
        if test_id not in runner_min:
            failures.append(f"必须存在的测试缺失: {test_id}")
            continue
        pinned = item.get("min_checks")
        if pinned is not None and runner_min[test_id] != pinned:
            failures.append(
                f"最低断言数未钉住: {test_id} 清单要求 min_checks={pinned}，"
                f"runner 条目为 {runner_min[test_id]}"
            )

    if failures:
        print("正式套件防缩水守卫失败：")
        for failure in failures:
            print(f"  {failure}")
        print("\n测试合并/删除须在 PR 证明覆盖未减少并同步更新 required_tests.json。")
        return 1
    print(
        f"正式套件防缩水守卫通过：清单 {len(required)} 项全部注册，"
        f"runner 共 {len(registered)} 项无重复。"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
