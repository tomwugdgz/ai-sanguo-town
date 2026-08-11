#!/bin/zsh
# 正式套件三分片并行执行(提速用,覆盖与串行完全一致):
#   分片1 = 1..55   (UI/门禁,单项快)
#   分片2 = 56..88  (世界集成)
#   分片3 = 89..end (慢速世界测试+存档家族——存档家族必须同分片,避免 user:// 写冲突)
# 任一分片红则整体红。串行入口 run_formal_release_story_suite.sh 保留不动,
# CI 仍用串行入口;本地验收可用本脚本。

set -u
script_dir="${0:A:h}"
suite="$script_dir/run_formal_release_story_suite.sh"
temp_base="${TMPDIR:-/tmp}"
log1="$(mktemp "$temp_base/ai-town-shard1.XXXXXX")"
log2="$(mktemp "$temp_base/ai-town-shard2.XXXXXX")"
log3="$(mktemp "$temp_base/ai-town-shard3.XXXXXX")"

cleanup() {
	rm -f "$log1" "$log2" "$log3"
}
trap cleanup EXIT

AI_TOWN_FORMAL_RELEASE_START_AT=1 AI_TOWN_FORMAL_RELEASE_END_AT=55 \
	"$suite" >"$log1" 2>&1 &
pid1=$!
AI_TOWN_FORMAL_RELEASE_START_AT=56 AI_TOWN_FORMAL_RELEASE_END_AT=88 \
	"$suite" >"$log2" 2>&1 &
pid2=$!
AI_TOWN_FORMAL_RELEASE_START_AT=89 \
	"$suite" >"$log3" 2>&1 &
pid3=$!

overall=0
wait "$pid1" || overall=1
wait "$pid2" || overall=1
wait "$pid3" || overall=1

print "===== 分片1(1-55) ====="
cat "$log1"
print "===== 分片2(56-88) ====="
cat "$log2"
print "===== 分片3(89-末) ====="
cat "$log3"

if (( overall != 0 )); then
	print -u2 "FORMAL_RELEASE_STORY_SUITE_PARALLEL_FAIL"
	exit 1
fi
total=0
for log in "$log1" "$log2" "$log3"; do
	shard_checks=$(grep -oE 'FORMAL_RELEASE_STORY_SUITE_PASS checks=[0-9]+' "$log" | grep -oE '[0-9]+$')
	if [[ -z "$shard_checks" ]]; then
		print -u2 "FORMAL_RELEASE_STORY_SUITE_PARALLEL_FAIL: 分片缺少通过标记"
		exit 1
	fi
	total=$((total + shard_checks))
done
print "FORMAL_RELEASE_STORY_SUITE_PARALLEL_PASS checks=$total"
