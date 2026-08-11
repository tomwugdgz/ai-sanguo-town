#!/bin/zsh

set -euo pipefail

project_root="${0:A:h:h}"
test_script="res://tests/game_flow_host_formal_entry_test.gd"
pass_marker="GAME_FLOW_HOST_FORMAL_ENTRY_PASS"
timeout_seconds="${AI_TOWN_FORMAL_ENTRY_TIMEOUT_SECONDS:-600}"
qa_name="ai-town-automated-formal-story-$$"
temp_base="${TMPDIR:-/tmp}"
temp_root="$(mktemp -d "$temp_base/ai-town-formal-story.XXXXXX")"
temp_game="$temp_root/game"
log_path="$temp_root/formal-entry.log"
if [[ "$(uname -s)" == "Darwin" ]]; then
	default_userdata_root="${HOME}/Library/Application Support/Godot/app_userdata"
else
	default_userdata_root="${HOME}/.local/share/godot/app_userdata"
fi
godot_userdata_root="${GODOT_USERDATA_ROOT:-$default_userdata_root}"
qa_user_root="$godot_userdata_root/$qa_name"

resolve_godot_bin() {
	if [[ -n "${GODOT_BIN:-}" ]]; then
		print -r -- "$GODOT_BIN"
		return 0
	fi
	local command_name
	for command_name in godot godot4; do
		if command -v "$command_name" >/dev/null 2>&1; then
			command -v "$command_name"
			return 0
		fi
	done
	local app_bin
	for app_bin in \
		"/Applications/Godot.app/Contents/MacOS/Godot" \
		"$HOME/Applications/Godot.app/Contents/MacOS/Godot"; do
		if [[ -x "$app_bin" ]]; then
			print -r -- "$app_bin"
			return 0
		fi
	done
	return 1
}

if ! godot_bin="$(resolve_godot_bin)"; then
	print -u2 "Godot executable not found; set GODOT_BIN or add godot/godot4 to PATH."
	exit 2
fi

cleanup() {
	if [[ "$temp_root" == "$temp_base"/ai-town-formal-story.* ]]; then
		rm -rf "$temp_root"
	fi
	if [[ "$qa_user_root" == \
		"$godot_userdata_root/ai-town-automated-formal-story-"* \
	]]; then
		rm -rf "$qa_user_root"
	fi
}
trap cleanup EXIT

if [[ ! -x "$godot_bin" ]]; then
	print -u2 "Godot 4.7.1 executable not found: $godot_bin"
	exit 2
fi

mkdir -p "$temp_game"
# Keep the full imported project state while isolating project name and user://.
if [[ "$(uname -s)" == "Darwin" ]]; then
	# APFS clone-on-write avoids duplicating the multi-gigabyte asset tree.
	cp -cR "$project_root/." "$temp_game/"
else
	# GNU cp：支持 reflink 的文件系统走克隆，其余自动回退为普通复制。
	cp -a --reflink=auto "$project_root/." "$temp_game/"
fi

# 用 perl 做原位替换：BSD 与 GNU sed 的 -i 语法不兼容，perl 两边一致
# （本脚本已依赖 /usr/bin/perl 做超时控制）。
/usr/bin/perl -pi -e \
	"s/^config\\/name=.*/config\\/name=\"$qa_name\"/" \
	"$temp_game/project.godot"

import_log_path="$temp_root/editor-import.log"
set +e
/usr/bin/perl -e \
	'$timeout = shift @ARGV; alarm $timeout; exec @ARGV;' \
	"$timeout_seconds" \
	"$godot_bin" \
	--headless \
	--editor \
	--path "$temp_game" \
	--quit \
	>"$import_log_path" 2>&1
import_exit_code=$?
set -e

if (( import_exit_code != 0 )); then
	print -u2 \
		"ISOLATED_FORMAL_ENTRY_STORY_FAIL import_exit=$import_exit_code timeout=${timeout_seconds}s"
	tail -n 120 "$import_log_path" >&2
	exit "$import_exit_code"
fi
if rg -q 'SCRIPT ERROR:|Parse Error:|Failed to load script' "$import_log_path"; then
	print -u2 "ISOLATED_FORMAL_ENTRY_STORY_FAIL import_script_error=true"
	rg -n 'SCRIPT ERROR:|Parse Error:|Failed to load script' "$import_log_path" >&2
	exit 3
fi
if rg -q '^ERROR:' "$import_log_path"; then
	print -u2 "ISOLATED_FORMAL_ENTRY_STORY_FAIL import_engine_error=true"
	rg -n '^ERROR:' "$import_log_path" >&2
	exit 3
fi

set +e
/usr/bin/perl -e \
	'$timeout = shift @ARGV; alarm $timeout; exec @ARGV;' \
	"$timeout_seconds" \
	"$godot_bin" \
	--headless \
	--path "$temp_game" \
	--script "$test_script" \
	>"$log_path" 2>&1
exit_code=$?
set -e

if (( exit_code != 0 )); then
	print -u2 \
		"ISOLATED_FORMAL_ENTRY_STORY_FAIL exit=$exit_code timeout=${timeout_seconds}s"
	tail -n 120 "$log_path" >&2
	exit "$exit_code"
fi
if rg -q 'SCRIPT ERROR:|Parse Error:|Failed to load script' "$log_path"; then
	print -u2 "ISOLATED_FORMAL_ENTRY_STORY_FAIL script_error=true"
	rg -n 'SCRIPT ERROR:|Parse Error:|Failed to load script' "$log_path" >&2
	exit 3
fi
# 精确允许列表：本故事测试会故意移除 Gateway 验证失败路径，
# 生产代码经 push_error 打出下面这一条（Godot 4.7 中 push_error
# 输出即行首 ERROR:）。除这一条外的任何引擎错误仍判失败。
allowed_error_pattern='^ERROR: Agent Gateway 初始化失败：当前 session 要求正式 Agent Gateway。$'
unexpected_engine_errors="$(rg '^ERROR:' "$log_path" | rg -v "$allowed_error_pattern" || true)"
if [[ -n "$unexpected_engine_errors" ]]; then
	print -u2 "ISOLATED_FORMAL_ENTRY_STORY_FAIL engine_error=true"
	print -r -- "$unexpected_engine_errors" >&2
	exit 3
fi
if ! rg -Fq "$pass_marker" "$log_path"; then
	print -u2 "ISOLATED_FORMAL_ENTRY_STORY_FAIL missing_pass_marker=true"
	tail -n 120 "$log_path" >&2
	exit 4
fi

print "ISOLATED_FORMAL_ENTRY_STORY_PASS"
