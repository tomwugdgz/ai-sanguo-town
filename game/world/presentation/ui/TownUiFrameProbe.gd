extends RefCounted

# A1 慢帧探针(docs/帧预算与节拍解耦方案.md):互斥口径分段计时,按渲染帧编号关联。
# 仅当 AI_TOWN_UI_FRAME_PROBE=1 时由各宿主 load 本文件;关闭时宿主的探针引用
# 保持 null,调用点零开销、零分配,本文件不进正式启动路径。
# 口径:adapterBuildUsec / adapterNormalizeAndDiffUsec / hudApplyUsec 互斥;
# adapterRefreshInclusiveUsec 只作总区间;adapterExclusiveUsec 在汇总时派生
# (inclusive - hudApply,负值计异常并按 0 记)。frameTotalUsec = TownRuntime
# totalUsec + adapterRefreshInclusiveUsec,分布覆盖全部采样帧;分段键的分位数
# 按"发生该段的帧"计(单次构建口径)。

const ENV_FLAG := "AI_TOWN_UI_FRAME_PROBE"
const SLOW_FRAME_USEC := 10_000
const OVER_16_7_USEC := 16_700
const OVER_25_USEC := 25_000
const FLUSH_INTERVAL_MSEC := 30_000
const SLOW_DETAIL_LIMIT := 20

static var _frames: Dictionary = {}
static var _last_flush_msec := 0


static func enabled_by_environment() -> bool:
	return OS.get_environment(ENV_FLAG) == "1"


static func record(frame: int, key: String, usec: int) -> void:
	if not _frames.has(frame):
		_frames[frame] = {}
	var entry: Dictionary = _frames[frame]
	entry[key] = int(entry.get(key, 0)) + usec


static func maybe_flush() -> void:
	var now := Time.get_ticks_msec()
	if _last_flush_msec == 0:
		_last_flush_msec = now
		return
	if now - _last_flush_msec < FLUSH_INTERVAL_MSEC:
		return
	_last_flush_msec = now
	flush()


static func flush() -> void:
	if _frames.is_empty():
		return
	var negative_exclusive := 0
	var slow := 0
	var over_16_7 := 0
	var over_25 := 0
	var keys: Dictionary = {}
	var slow_details: Array[Dictionary] = []
	for frame: int in _frames:
		var entry: Dictionary = _frames[frame]
		if entry.has("adapterRefreshInclusiveUsec"):
			var exclusive := (
				int(entry["adapterRefreshInclusiveUsec"])
				- int(entry.get("hudApplyUsec", 0))
			)
			if exclusive < 0:
				negative_exclusive += 1
				exclusive = 0
			entry["adapterExclusiveUsec"] = exclusive
		var frame_total := (
			int(entry.get("totalUsec", 0))
			+ int(entry.get("adapterRefreshInclusiveUsec", 0))
		)
		entry["frameTotalUsec"] = frame_total
		if frame_total > SLOW_FRAME_USEC:
			slow += 1
			var detail := entry.duplicate()
			detail["frame"] = frame
			slow_details.append(detail)
		if frame_total > OVER_16_7_USEC:
			over_16_7 += 1
		if frame_total > OVER_25_USEC:
			over_25 += 1
		for key: String in entry:
			keys[key] = true
	# 慢帧明细取最重的 N 个,不是最早的 N 个——避免一次爆发占满全部名额。
	slow_details.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a.get("frameTotalUsec", 0)) > int(b.get("frameTotalUsec", 0))
	)
	if slow_details.size() > SLOW_DETAIL_LIMIT:
		slow_details.resize(SLOW_DETAIL_LIMIT)
	print(
		"AI_TOWN_UI_FRAME_PROBE_SUMMARY frames=%d slow_gt10ms=%d over16.7ms=%d over25ms=%d negative_exclusive=%d"
		% [_frames.size(), slow, over_16_7, over_25, negative_exclusive]
	)
	var sorted_keys: Array = keys.keys()
	sorted_keys.sort()
	for key: String in sorted_keys:
		var samples: Array[int] = []
		for entry: Dictionary in _frames.values():
			if entry.has(key):
				samples.append(int(entry[key]))
		samples.sort()
		print(
			"AI_TOWN_UI_FRAME_PROBE_KEY key=%s count=%d p50=%d p95=%d p99=%d max=%d"
			% [
				key,
				samples.size(),
				_percentile(samples, 0.50),
				_percentile(samples, 0.95),
				_percentile(samples, 0.99),
				samples[samples.size() - 1],
			]
		)
	for detail: Dictionary in slow_details:
		print("AI_TOWN_UI_FRAME_PROBE_SLOW %s" % [JSON.stringify(detail)])


static func reset() -> void:
	_frames.clear()
	_last_flush_msec = 0


static func _percentile(sorted_samples: Array[int], ratio: float) -> int:
	if sorted_samples.is_empty():
		return 0
	var index := int(floor(ratio * float(sorted_samples.size() - 1)))
	return sorted_samples[index]
