#!/bin/zsh

set -euo pipefail

project_root="${0:A:h:h}"
godot_bin="${GODOT_BIN:-/Users/hao/Downloads/Godot.app/Contents/MacOS/Godot}"
qa_name="ai-town-formal-real-oc-$$"
temp_base="${TMPDIR:-/tmp}"
temp_root="$(mktemp -d "$temp_base/ai-town-real-oc.XXXXXX")"
temp_game="$temp_root/game"
source_user_root="${HOME}/Library/Application Support/Godot/app_userdata/ai-town"
userdata_root="${HOME}/Library/Application Support/Godot/app_userdata"
qa_user_root="$userdata_root/$qa_name"
credential_export="$source_user_root/provider_credentials.qa_export.enc"
qa_credential_export="$qa_user_root/provider_credentials.qa_export.enc"
log_path="$temp_root/formal-real-oc.log"
timeout_seconds="${AI_TOWN_REAL_OC_TIMEOUT_SECONDS:-2400}"

cleanup() {
	/bin/rm -f "$credential_export"
	/bin/rm -f "$qa_credential_export"
	if [[ "$qa_user_root" == "$userdata_root/ai-town-formal-real-oc-"* ]]; then
		/usr/bin/find "$qa_user_root" -depth -delete 2>/dev/null || true
	fi
	if [[ "$temp_root" == "$temp_base/ai-town-real-oc."* ]]; then
		/usr/bin/find "$temp_root" -depth -delete 2>/dev/null || true
	fi
}
trap cleanup EXIT

if [[ ! -x "$godot_bin" ]]; then
	print -u2 "ISOLATED_FORMAL_REAL_OC_FAIL godot_missing=true"
	exit 2
fi
if [[ ! -f "$source_user_root/provider_settings.json" ]]; then
	print -u2 "ISOLATED_FORMAL_REAL_OC_FAIL provider_settings_missing=true"
	exit 2
fi

mkdir -p "$temp_game"
cp -cR "$project_root/." "$temp_game/"
/usr/bin/perl -pi -e \
	"s/^config\\/name=.*/config\\/name=\"$qa_name\"/" \
	"$temp_game/project.godot"

set +e
AI_TOWN_QA_PROJECT_NAME="$qa_name" \
	"$godot_bin" --headless --path "$project_root" \
	--script res://tests/town_provider_credential_isolated_export.gd \
	>"$temp_root/credential-export.log" 2>&1
credential_exit=$?
set -e
if (( credential_exit != 0 )); then
	print -u2 "ISOLATED_FORMAL_REAL_OC_FAIL credential_exit=$credential_exit"
	tail -n 80 "$temp_root/credential-export.log" >&2
	exit "$credential_exit"
fi
if ! rg -Fq "TOWN_PROVIDER_CREDENTIAL_ISOLATED_EXPORT_PASS" \
	"$temp_root/credential-export.log"; then
	print -u2 "ISOLATED_FORMAL_REAL_OC_FAIL credential_export=true"
	tail -n 80 "$temp_root/credential-export.log" >&2
	exit 3
fi

mkdir -p "$qa_user_root"
cp "$source_user_root/provider_settings.json" "$qa_user_root/provider_settings.json"
if [[ -f "$qa_credential_export" ]]; then
	mv "$qa_credential_export" "$qa_user_root/provider_credentials.enc"
else
	mv "$credential_export" "$qa_user_root/provider_credentials.enc"
fi

set +e
"$godot_bin" --headless --editor --path "$temp_game" --quit \
	>"$temp_root/import.log" 2>&1
import_exit=$?
set -e
if (( import_exit != 0 )); then
	print -u2 "ISOLATED_FORMAL_REAL_OC_FAIL import_exit=$import_exit"
	tail -n 120 "$temp_root/import.log" >&2
	exit "$import_exit"
fi
if rg -q 'SCRIPT ERROR:|Parse Error:|Failed to load script|^ERROR:' \
	"$temp_root/import.log"; then
	print -u2 "ISOLATED_FORMAL_REAL_OC_FAIL import=true"
	rg -n 'SCRIPT ERROR:|Parse Error:|Failed to load script|^ERROR:' \
		"$temp_root/import.log" >&2
	exit 4
fi

set +e
/usr/bin/perl -e '$timeout = shift @ARGV; alarm $timeout; exec @ARGV;' \
	"$timeout_seconds" \
	env AI_TOWN_RUN_FORMAL_REAL_OC_LIFE=1 \
	AI_TOWN_REAL_OC_RUN_MSEC="${AI_TOWN_REAL_OC_RUN_MSEC:-300000}" \
	"$godot_bin" --headless --path "$temp_game" \
	--script res://tests/town_formal_real_oc_life_test.gd \
	>"$log_path" 2>&1
exit_code=$?
set -e

rg -n \
	'TOWN_FORMAL_REAL_OC_(LIFE_REPORT|START_FAILURE)|TOWN_FORMAL_REAL_OC_LIFE_(PASS|FAIL)|^ERROR:|SCRIPT ERROR:' \
	"$log_path" || true
if (( exit_code != 0 )); then
	print -u2 "ISOLATED_FORMAL_REAL_OC_FAIL exit=$exit_code"
	tail -n 160 "$log_path" >&2
	exit "$exit_code"
fi
if ! rg -Fq "TOWN_FORMAL_REAL_OC_LIFE_PASS" "$log_path"; then
	print -u2 "ISOLATED_FORMAL_REAL_OC_FAIL missing_pass=true"
	tail -n 160 "$log_path" >&2
	exit 5
fi
print "ISOLATED_FORMAL_REAL_OC_PASS"
