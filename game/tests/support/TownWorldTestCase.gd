class_name TownWorldTestCase
extends SceneTree
## 世界系统测试基座：统一世界构建、唤醒取用、决定构造与断言收尾。
##
## 世界侧测试此前每个文件各自重建这套样板（建数据、载开局、取唤醒、拼「去 /
## 搭话 / 待着」决定、自定义 _expect/_finish），逐字重复。基座把这部分收敛为
## 一处，子类只写场景与断言。Agent 侧的 AgentTestCase 是同一思路。


const SOURCE_DIR := "res://world/data/town/source"
const OPENING_PATH := "res://tests/fixtures/town_world_opening.json"
const BUILDER := preload("res://world/data/town/TownWorldDataBuilder.gd")
const OPENING := preload("res://world/runtime/TownWorldOpeningConfig.gd")
const WORLD := preload("res://world/runtime/TownWorldRuntime.gd")

var _failures: Array[String] = []
var _checks := 0

var _cached_data: Dictionary = {}


# —— 断言 ——

func _expect(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(message)


func _expect_equal(actual: Variant, expected: Variant, message: String) -> void:
	_checks += 1
	if actual != expected:
		_failures.append("%s: expected %s, got %s" % [message, str(expected), str(actual)])


func _finish_suite(pass_label: String) -> void:
	var exit_code := 0 if _failures.is_empty() else 1
	if _failures.is_empty():
		print("%s checks=%d" % [pass_label, _checks])
	else:
		for failure: String in _failures:
			printerr("%s_FAIL: %s" % [pass_label, failure])
	# 合并套件在 _initialize 中同步完成大量断言；给自动加载音频节点几帧
	# 完成 _ready，随后才能可靠停止播放器并释放解码对象。
	for _index in 5:
		await process_frame
	var audio_controller := root.get_node_or_null("TownAudioController")
	if audio_controller != null and audio_controller.has_method("prepare_shutdown"):
		audio_controller.call("prepare_shutdown")
	await create_timer(0.3, true, false, true).timeout
	quit(exit_code)


# —— 世界构建 ——

## 世界数据按源码目录构建一次后缓存，每次调用返回深拷贝，
## 与逐次重建等价但省掉重复的源文件解析。
func _build_data() -> Dictionary:
	if _cached_data.is_empty():
		_cached_data = BUILDER.build_from_source(SOURCE_DIR)
	return _cached_data.duplicate(true)


func _load_opening(data: Dictionary) -> Dictionary:
	var result := OPENING.load_config(OPENING_PATH, data) as Dictionary
	_expect_equal(result.get("ok"), true, "开局数据可加载")
	return (result.get("config", {}) as Dictionary).duplicate(true)


func _set_resident_outdoor_state(
	opening: Dictionary,
	resident_name: String,
	position: Vector2,
) -> void:
	for value: Variant in opening.get("residents", []) as Array:
		var resident := value as Dictionary
		if String(resident.get("attributes", {}).get("name", "")) != resident_name:
			continue
		resident["worldState"] = {
			"place": "社区花园",
			"spaceId": "town_outdoor",
			"regionId": "outdoor_garden_01",
			"position": [position.x, position.y],
			"doing": "在社区花园里",
			"body": {"困": "不困", "饿": "不饿", "累": "不累"},
		}
		return


## 社区花园开局：唐小满与阿禾同处户外，供移动与搭话场景使用。
func _garden_opening(data: Dictionary, legality_message: String) -> Dictionary:
	var opening := _load_opening(data)
	_set_resident_outdoor_state(opening, "唐小满", Vector2(3396, 2772))
	_set_resident_outdoor_state(opening, "阿禾", Vector2(3396, 2772))
	_expect_equal(OPENING.validate(opening, data), [], legality_message)
	return opening


# —— 唤醒与决定 ——

func _take_wake(world: Object, resident_name: String) -> Dictionary:
	return _request_for(
		world.call("take_pending_decision_requests", [resident_name]) as Array[Dictionary],
		resident_name,
	)


func _request_for(requests: Array[Dictionary], resident_name: String) -> Dictionary:
	for request in requests:
		if String(request.get("residentName", "")) == resident_name:
			return (request.get("wakePacket", {}) as Dictionary).duplicate(true)
	return {}


func _nearby_resident_id(wake: Dictionary, target: String) -> String:
	for value: Variant in (wake.get("snapshot", {}) as Dictionary).get("nearby", []) as Array:
		var person := value as Dictionary
		if String(person.get("name", "")) == target:
			return String(person.get("resident_id", ""))
	return ""


func _go(wake: Dictionary, place: String) -> Dictionary:
	var decision_id := String(wake.get("decision_id", ""))
	return {
		"decision_id": decision_id,
		"handling": "replace_current",
		"action": {
			"action_id": "%s-go" % decision_id,
			"type": "去",
			"place": place,
			"line": "去%s" % place,
		},
	}


func _talk(wake: Dictionary, target: String, narration: String) -> Dictionary:
	var decision_id := String(wake.get("decision_id", ""))
	return {
		"decision_id": decision_id,
		"handling": "replace_current",
		"action": {
			"action_id": "%s-talk" % decision_id,
			"type": "搭话",
			"target_resident_id": _nearby_resident_id(wake, target),
			"say": "等会儿一起去看看公告。",
			"narration": narration,
			"photos": [],
		},
	}


func _wait(wake: Dictionary, line: String = "在这里待着") -> Dictionary:
	var decision_id := String(wake.get("decision_id", ""))
	return {
		"decision_id": decision_id,
		"handling": "replace_current",
		"action": {
			"action_id": "%s-wait" % decision_id,
			"type": "待着",
			"line": line,
		},
	}


func _has_event(wake: Dictionary, event_type: String) -> bool:
	for event_value: Variant in wake.get("events", []) as Array:
		if String((event_value as Dictionary).get("type", "")) == event_type:
			return true
	return false


# —— 存档事务通用 ——

func _candidate_token(result: Dictionary) -> String:
	return String((result.get("candidate", {}) as Dictionary).get("token", ""))


func _observable_state(world: Object) -> Dictionary:
	return {
		"revision": int(world.call("get_world_revision")),
		"time": world.call("get_time"),
		"weather": String(world.call("get_weather")),
		"identity": world.call("get_resident_identity_snapshot"),
		"lifecycle": world.call("get_lifecycle_state"),
	}
