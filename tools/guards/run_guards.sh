#!/bin/sh
# 三守卫 + 套件防缩水一键检查（CI 与本地共用）。
# 口径与机制见 docs/屎山消灭计划.md 批次 A；各脚本可单独运行看详情。
set -eu
guards_dir="$(cd "$(dirname "$0")" && pwd)"
status=0
python3 "$guards_dir/line_ratchet.py" --check || status=1
python3 "$guards_dir/dynamic_call_scan.py" --check || status=1
python3 "$guards_dir/zero_reference_scan.py" --check || status=1
python3 "$guards_dir/required_tests_check.py" || status=1
python3 "$guards_dir/cross_platform_text_check.py" || status=1
python3 "$guards_dir/../sync_readme_updates.py" --check || status=1
if [ "$status" -ne 0 ]; then
	echo "GUARDS_FAILED"
	exit 1
fi
echo "GUARDS_PASS"
