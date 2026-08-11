extends "res://tests/support/TownWorldTestCase.gd"


const PLAYBACK := preload(
	"res://world/presentation/ui/TownConversationBubblePlayback.gd"
)


func _initialize() -> void:
	call_deferred("_run_all")


func _run_all() -> void:
	_test_sentence_playback_and_model_gap()
	_test_end_waits_for_last_bubble()
	_test_pause_resume_keeps_progress()
	_finish_suite("TOWN_CONVERSATION_BUBBLE_PLAYBACK_PASS")


func _test_sentence_playback_and_model_gap() -> void:
	var playback := PLAYBACK.new()
	var first_state := _conversation(
		"conversation-bubble-1",
		"active",
		[{
			"turn_id": 1,
			"speaker": "林岚",
			"speaker_resident_id": "resident-lin",
			"say": "先去看看花圃。",
		}],
	)
	playback.ingest(first_state, 1000)
	var visible := playback.visible_items(1000)
	_expect_equal(visible.size(), 1, "有已确认发言时生成一个气泡")
	_expect_equal(
		(visible[0] as Dictionary).get("bubbleText"),
		"先去看看花圃。",
		"气泡显示真实发言而不是旁观标签",
	)
	playback.advance(2199)
	_expect_equal(playback.visible_items(2199).size(), 1, "单句气泡停留满 1.2 秒")
	playback.advance(2200)
	_expect_equal(
		playback.visible_items(2200).size(),
		0,
		"模型还没给下一句时不显示连续省略号",
	)

	var reply_state := first_state.duplicate(true)
	(reply_state.get("turns", []) as Array).append({
		"turn_id": 2,
		"speaker": "唐小满",
		"speaker_resident_id": "resident-tang",
		"say": "好呀，我们一起去。",
	})
	playback.ingest(reply_state, 2300)
	visible = playback.visible_items(2300)
	_expect_equal(visible.size(), 1, "模型回复到达后恢复显示下一句")
	_expect_equal(
		(visible[0] as Dictionary).get("bubbleText"),
		"好呀，我们一起去。",
		"下一句只在真实回复到达后贴出",
	)


func _test_end_waits_for_last_bubble() -> void:
	var playback := PLAYBACK.new()
	var state := _conversation(
		"conversation-bubble-2",
		"active",
		[{
			"turn_id": 1,
			"speaker": "林岚",
			"speaker_resident_id": "resident-lin",
			"say": "这句播完，对话就结束。",
		}],
	)
	playback.ingest(state, 3000)
	var ended := state.duplicate(true)
	ended["status"] = "ended"
	playback.ingest(ended, 3500)
	_expect_equal(playback.visible_items(4199).size(), 1, "世界结束后最后一句仍然可见")
	_expect_equal(playback.visible_items(4200).size(), 0, "最后一句播完才清掉气泡")


func _test_pause_resume_keeps_progress() -> void:
	var playback := PLAYBACK.new()
	playback.ingest(
		_conversation(
			"conversation-bubble-3",
			"active",
			[{
				"turn_id": 1,
				"speaker": "林岚",
				"speaker_resident_id": "resident-lin",
				"say": "暂停后继续播放。",
			}],
		),
		5000,
	)
	playback.set_paused(true, 5500)
	playback.advance(8000)
	_expect_equal(playback.visible_items(8000).size(), 1, "暂停期间不推进气泡")
	playback.set_paused(false, 8000)
	_expect_equal(playback.visible_items(8699).size(), 1, "退出暂停后恢复剩余展示时间")
	_expect_equal(playback.visible_items(8700).size(), 0, "恢复后仍按 1.2 秒结束")


func _conversation(
	conversation_id: String,
	status: String,
	turns: Array,
) -> Dictionary:
	return {
		"conversationId": conversation_id,
		"participants": ["resident-lin", "resident-tang"],
		"status": status,
		"turns": turns,
	}
