#!/usr/bin/env python3
"""Protect byte-sensitive text assets from Windows CRLF checkout changes."""

from __future__ import annotations

import hashlib
import json
import subprocess
from pathlib import Path

from guard_common import REPO_ROOT


ATTRIBUTES_PATH = REPO_ROOT / ".gitattributes"
REQUIRED_RULE = "* text=auto eol=lf"
RIG_MANIFEST = REPO_ROOT / (
    "game/assets/characters/resident_2d_rig_v1/direction_branches/"
    "identity_unification_v1_pending/turntable_strip_v1/"
    "production_frozen_v2/whitebody_freeze_manifest_v2.json"
)


def fail(message: str) -> None:
    raise SystemExit(f"跨平台文本守卫失败：{message}")


def check_attributes() -> None:
    if not ATTRIBUTES_PATH.is_file():
        fail("仓库根目录缺少 .gitattributes")
    rules = [
        line.strip()
        for line in ATTRIBUTES_PATH.read_text(encoding="utf-8").splitlines()
        if line.strip() and not line.lstrip().startswith("#")
    ]
    if REQUIRED_RULE not in rules:
        fail(f".gitattributes 必须包含：{REQUIRED_RULE}")

    checked = subprocess.run(
        [
            "git",
            "check-attr",
            "text",
            "eol",
            "--",
            "game/world/data/town/town_world.json",
            "game/world/maps/town/TownBase.gd",
        ],
        cwd=REPO_ROOT,
        check=True,
        capture_output=True,
        text=True,
    ).stdout
    for path in [
        "game/world/data/town/town_world.json",
        "game/world/maps/town/TownBase.gd",
    ]:
        if f"{path}: text: auto" not in checked or f"{path}: eol: lf" not in checked:
            fail(f"{path} 未稳定应用 text=auto、eol=lf")


def check_tracked_text_has_no_carriage_returns() -> None:
    result = subprocess.run(
        ["git", "grep", "-Il", "\r", "--", "."],
        cwd=REPO_ROOT,
        check=False,
        capture_output=True,
        text=True,
    )
    if result.returncode not in (0, 1):
        fail(result.stderr.strip() or "无法扫描已跟踪文本")
    paths = [line for line in result.stdout.splitlines() if line]
    if paths:
        fail("以下已跟踪文本仍包含 CR/CRLF：\n" + "\n".join(paths))


def check_rig_source_hashes() -> None:
    manifest = json.loads(RIG_MANIFEST.read_text(encoding="utf-8"))
    sources = manifest.get("rig_sources")
    if not isinstance(sources, dict):
        fail("白模冻结清单缺少 rig_sources")
    checked = 0
    for source_name, descriptor in sources.items():
        if not isinstance(descriptor, dict):
            continue
        relative = descriptor.get("path")
        expected = descriptor.get("sha256")
        if not isinstance(relative, str) or not isinstance(expected, str):
            fail(f"rig_sources.{source_name} 缺少 path 或 sha256")
        source_path = (RIG_MANIFEST.parent / relative).resolve()
        try:
            source_path.relative_to(REPO_ROOT)
        except ValueError:
            fail(f"rig_sources.{source_name} 指向仓库外部")
        if not source_path.is_file():
            fail(f"rig_sources.{source_name} 文件不存在：{relative}")
        payload = source_path.read_bytes()
        if b"\r" in payload:
            fail(f"rig_sources.{source_name} 包含 CR/CRLF")
        actual = hashlib.sha256(payload).hexdigest()
        if actual != expected:
            fail(
                f"rig_sources.{source_name} 摘要不一致："
                f"expected={expected} actual={actual}"
            )
        checked += 1
    if checked != 4:
        fail(f"应校验 4 个 rig 源文件，实际校验 {checked} 个")


def main() -> None:
    check_attributes()
    check_tracked_text_has_no_carriage_returns()
    check_rig_source_hashes()
    print("CROSS_PLATFORM_TEXT_PASS rig_sources=4")


if __name__ == "__main__":
    main()
