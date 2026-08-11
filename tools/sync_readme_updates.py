#!/usr/bin/env python3
"""将更新日志中的最新一期摘要同步到 README。"""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parent.parent
CHANGELOG_PATH = ROOT / "更新日志.md"
README_PATH = ROOT / "README.md"
START_MARKER = "<!-- latest-update:start -->"
END_MARKER = "<!-- latest-update:end -->"
RELEASE_HEADING = re.compile(
    r"^## (?P<title>\d{4} 年 \d{1,2} 月 \d{1,2} 日更新)\s*$",
    re.MULTILINE,
)


def latest_update_block(changelog: str) -> str:
    match = RELEASE_HEADING.search(changelog)
    if match is None:
        raise ValueError("更新日志中没有找到按日期书写的更新章节")

    body = changelog[match.end() :]
    paragraphs: list[str] = []
    current: list[str] = []

    for line in body.splitlines():
        stripped = line.strip()
        if stripped.startswith("#"):
            break
        if not stripped:
            if current:
                paragraphs.append("\n".join(current))
                current = []
            continue
        current.append(stripped)

    if current:
        paragraphs.append("\n".join(current))
    if not paragraphs:
        raise ValueError("最新更新章节缺少摘要段落")

    return "\n".join(
        [
            START_MARKER,
            f"### {match.group('title')}",
            "",
            paragraphs[0],
            "",
            "[查看完整《更新日志》](更新日志.md)",
            END_MARKER,
        ]
    )


def synchronized_readme(readme: str, update_block: str) -> str:
    start = readme.find(START_MARKER)
    end = readme.find(END_MARKER)
    if start < 0 or end < 0 or end < start:
        raise ValueError("README 缺少最新更新同步标记")
    end += len(END_MARKER)
    return readme[:start] + update_block + readme[end:]


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--check",
        action="store_true",
        help="只检查 README 是否已经同步，不修改文件",
    )
    args = parser.parse_args()

    try:
        changelog = CHANGELOG_PATH.read_text(encoding="utf-8")
        readme = README_PATH.read_text(encoding="utf-8")
        expected = synchronized_readme(readme, latest_update_block(changelog))
    except (OSError, ValueError) as error:
        print(f"README_UPDATE_SYNC_FAILED: {error}", file=sys.stderr)
        return 1

    if args.check:
        if readme != expected:
            print(
                "README_UPDATE_SYNC_FAILED: 请运行 "
                "python3 tools/sync_readme_updates.py",
                file=sys.stderr,
            )
            return 1
        print("README_UPDATE_SYNC_PASS")
        return 0

    README_PATH.write_text(expected, encoding="utf-8")
    print("README_UPDATE_SYNCED")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
