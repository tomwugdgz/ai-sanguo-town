extends "res://tests/agent/support/AgentTestCase.gd"


const DebugBatchScript := preload("res://agent/debug/DebugBatch.gd")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var batch: RefCounted = DebugBatchScript.new()
	var continuous := batch.call("parse", {
		"schema": "agent-debug-campaign/v1",
		"campaign_id": "conversation-sample",
		"mode": "continuous",
		"runs": [{
			"id": "same-resident-twice",
			"actions": [
				{
					"type": "conversation",
					"resident_id": "resident_lin_lan_01",
					"say": "早上好",
				},
				{
					"type": "conversation",
					"resident_id": "resident_lin_lan_01",
					"say": "再聊聊今天的计划",
				},
			],
		}, {
			"id": "another-resident",
			"actions": [{
				"type": "conversation",
				"resident_id": "resident_bai_zhi_01",
				"say": "最近还好吗？",
			}],
		}],
	}) as Dictionary
	_expect_equal(continuous.get("ok"), true, "接受面向游戏动作的连续 campaign")
	_expect_equal(continuous.get("mode"), "continuous", "保留连续会话模式")
	_expect_equal(
		(continuous.get("runs", []) as Array).size(),
		2,
		"连续 campaign 支持同居民多轮及多居民",
	)
	var isolated := batch.call("parse", {
		"schema": "agent-debug-campaign/v1",
		"mode": "isolated",
		"runs": [{
			"id": "one",
			"actions": [{"type": "announcement", "text": "集市开放"}],
		}],
	}) as Dictionary
	_expect_equal(isolated.get("ok"), true, "接受隔离运行模式")
	var legacy := batch.call("parse", {
		"schema": "agent-debug-batch/v1",
		"saves": [],
	}) as Dictionary
	_expect_equal(legacy.get("ok"), false, "拒绝已删除的 WakePacket 批测协议")
	var unsupported := batch.call("parse", {
		"schema": "agent-debug-campaign/v1",
		"mode": "continuous",
		"runs": [{"actions": [{"type": "raw_wake_packet"}]}],
	}) as Dictionary
	_expect_equal(unsupported.get("ok"), false, "文件输入不能绕过 World 伪造 WakePacket")
	_finish_suite("AGENT_DEBUG_BATCH_TEST_PASS")
