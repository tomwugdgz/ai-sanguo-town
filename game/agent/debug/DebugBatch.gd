class_name AgentDebugBatch
extends RefCounted


const AgentJsonScript := preload("res://agent/AgentJson.gd")
const SCHEMA := "agent-debug-campaign/v1"
const ACTION_TYPES: Array[String] = [
	"conversation",
	"conversation_reply",
	"conversation_end",
	"announcement",
	"advance_time",
	"weather",
]


func load_file(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return _failure(["无法读取批量文件：%s" % path])
	var value: Variant = JSON.parse_string(file.get_as_text())
	if typeof(value) != TYPE_DICTIONARY:
		return _failure(["批量文件必须是 JSON 对象"])
	return parse(AgentJsonScript.normalize_numbers(value))


func parse(value: Variant) -> Dictionary:
	if typeof(value) != TYPE_DICTIONARY:
		return _failure(["campaign 必须是对象"])
	var document := value as Dictionary
	if String(document.get("schema", "")) != SCHEMA:
		return _failure(["schema 必须是 %s" % SCHEMA])
	var mode := String(document.get("mode", "continuous"))
	if not ["continuous", "isolated"].has(mode):
		return _failure(["mode 必须是 continuous 或 isolated"])
	var runs_value: Variant = document.get("runs")
	if typeof(runs_value) != TYPE_ARRAY or (runs_value as Array).is_empty():
		return _failure(["runs 必须是非空数组"])
	var errors: Array[String] = []
	var runs: Array[Dictionary] = []
	for run_index in (runs_value as Array).size():
		var run_value: Variant = (runs_value as Array)[run_index]
		if typeof(run_value) != TYPE_DICTIONARY:
			errors.append("runs[%d] 必须是对象" % run_index)
			continue
		var run := (run_value as Dictionary).duplicate(true)
		var actions_value: Variant = run.get("actions")
		if typeof(actions_value) != TYPE_ARRAY or (actions_value as Array).is_empty():
			errors.append("runs[%d].actions 必须是非空数组" % run_index)
			continue
		for action_index in (actions_value as Array).size():
			var action_value: Variant = (actions_value as Array)[action_index]
			if typeof(action_value) != TYPE_DICTIONARY:
				errors.append(
					"runs[%d].actions[%d] 必须是对象" % [run_index, action_index],
				)
				continue
			var action_type := String((action_value as Dictionary).get("type", ""))
			if not ACTION_TYPES.has(action_type):
				errors.append(
					"runs[%d].actions[%d].type 不受支持：%s"
					% [run_index, action_index, action_type],
				)
		runs.append(run)
	if not errors.is_empty():
		return _failure(errors)
	return {
		"ok": true,
		"schema": SCHEMA,
		"campaignId": String(document.get("campaign_id", "")),
		"mode": mode,
		"runs": runs,
	}


func example() -> Dictionary:
	return {
		"schema": SCHEMA,
		"campaign_id": "resident-conversation-observation",
		"mode": "continuous",
		"runs": [{
			"id": "lin-lan-dialogues",
			"actions": [
				{
					"type": "conversation",
					"resident_id": "resident_lin_lan_01",
					"say": "早上好，今天镇上有什么新鲜事？",
				},
				{"type": "advance_time", "seconds": 2},
			],
		}],
	}


func _failure(errors: Array[String]) -> Dictionary:
	return {"ok": false, "errors": errors.duplicate()}
