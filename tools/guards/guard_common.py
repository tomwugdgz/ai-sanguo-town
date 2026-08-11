"""守卫脚本共用逻辑：仓库定位、生产代码范围、测试分类清单加载。

范围口径见 docs/屎山消灭计划.md 批次 A 之 2：
- 扫描 game/ 下全部生产 .gd 脚本；
- 按递归路径模式排除 game/tests/、game/addons/、**/tests/**、**/preflight/**、
  **/validation/**；
- 叠加 test_classification.json 中已分类（八类之一）的脚本——所有分类
  均为非生产脚本，逐步分类即逐步收窄扫描范围。
"""

from __future__ import annotations

import json
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent.parent
GAME_ROOT = REPO_ROOT / "game"
GUARDS_ROOT = REPO_ROOT / "tools" / "guards"

CLASSIFICATION_FILE = GUARDS_ROOT / "test_classification.json"

# 八类分类名（与计划批次 A 之 3、终态表一致）。
CATEGORIES = (
    "自动测试",
    "联网测试",
    "预检查",
    "手工预览",
    "截图采集",
    "资产工具",
    "夹具",
    "辅助",
)

# 递归排除的目录名（路径中任一层命中即排除）。
EXCLUDED_DIR_NAMES = {"tests", "preflight", "validation"}
# game/ 下整目录排除的顶层目录。
EXCLUDED_TOP_DIRS = {"addons"}


def load_classification() -> dict[str, str]:
    """返回 {repo 相对路径: 分类名}。文件缺失时返回空表。"""
    if not CLASSIFICATION_FILE.exists():
        return {}
    data = json.loads(CLASSIFICATION_FILE.read_text(encoding="utf-8"))
    entries = data.get("entries", {})
    for path, category in entries.items():
        if category not in CATEGORIES:
            raise SystemExit(
                f"test_classification.json 中 {path} 的分类 {category!r} "
                f"不在八类之内: {CATEGORIES}"
            )
    return entries


def rel(path: Path) -> str:
    return path.relative_to(REPO_ROOT).as_posix()


def is_excluded_production(path: Path) -> bool:
    """path 是否被排除在生产代码扫描范围之外（不含分类排除）。"""
    parts = path.relative_to(GAME_ROOT).parts
    if parts and parts[0] in EXCLUDED_TOP_DIRS:
        return True
    return any(part in EXCLUDED_DIR_NAMES for part in parts[:-1])


def production_gd_files() -> list[Path]:
    """按批次 A 之 2 口径返回生产 .gd 文件列表（排序稳定）。"""
    classified = load_classification()
    files = []
    for path in sorted(GAME_ROOT.rglob("*.gd")):
        if is_excluded_production(path):
            continue
        if rel(path) in classified:
            continue
        files.append(path)
    return files


def strip_line_comment(line: str) -> str:
    """去掉行内 # 注释，忽略字符串字面量中的 #。"""
    result = []
    quote = None
    i = 0
    while i < len(line):
        ch = line[i]
        if quote is None:
            if ch == "#":
                break
            if ch in ('"', "'"):
                quote = ch
            result.append(ch)
        else:
            result.append(ch)
            if ch == "\\":
                if i + 1 < len(line):
                    result.append(line[i + 1])
                    i += 1
            elif ch == quote:
                quote = None
        i += 1
    return "".join(result)
