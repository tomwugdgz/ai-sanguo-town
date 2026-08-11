extends "res://tests/agent/support/AgentPromptTestCase.gd"


func _initialize() -> void:
	var compiler_script := _load_prompt_compiler()
	if compiler_script != null:
		_test_overheard_conversation_keeps_both_participants(compiler_script)
		_test_photo_content_enters_model_message(compiler_script)
	_finish_prompt_test("AGENT_MULTIMODAL_PROMPT_PASS")


func _test_overheard_conversation_keeps_both_participants(compiler_script: Script) -> void:
	var wake := _wake_packet("overheard-1", "晴天")
	wake["events"] = [{
		"event_id": "overheard-event-1",
		"time": {"day": 1, "clock": "08:10", "period": "上午"},
		"type": "旁听",
		"conversation_id": "conversation-overheard",
		"speaker_resident_ids": [
			"resident-tang-xiao-man",
			"person-avatar-7",
		],
		"speakers": ["唐小满", "阿澈"],
		"turn": {
			"turn_id": 1,
			"speaker_resident_id": "resident-tang-xiao-man",
			"speaker": "唐小满",
			"say": "阿澈，你见过那只猫吗？",
			"narration": "",
			"photos": [],
		},
	}]
	var compiler: RefCounted = compiler_script.new(_initialization())
	var request: Dictionary = compiler.call("compile", wake, "")
	var messages := request.get("messages", []) as Array
	var user_text := String((messages[1] as Dictionary).get("content", ""))
	_expect(
		user_text.contains("resident-tang-xiao-man｜唐小满")
		and user_text.contains("person-avatar-7｜阿澈"),
		"decision prompt keeps both confirmed participants of an overheard conversation",
	)

func _test_photo_content_enters_model_message(compiler_script: Script) -> void:
	var resolver := FakePhotoContentResolver.new()
	var compiler: RefCounted = compiler_script.new(
		_initialization(),
		"res://prompts",
		resolver,
	)
	var wake := _wake_packet("photo-input-1", "晴天")
	wake["events"] = [{
		"event_id": "photo-turn-1",
		"time": {"day": 1, "clock": "08:10", "period": "上午"},
		"type": "搭话",
		"conversation_id": "conversation-photo",
		"turn": {
			"turn_id": 1,
			"speaker_resident_id": "person-avatar-7",
			"speaker": "阿澈",
			"say": "你见过这只猫吗？",
			"narration": "递来一张照片。",
			"photos": [{"ref": "chat-photo-37", "mime_type": "image/png"}],
		},
	}]
	var request: Dictionary = compiler.call("compile", wake, "")
	var messages := request.get("messages", []) as Array
	var content: Variant = (messages[1] as Dictionary).get("content")
	_expect_equal(typeof(content), TYPE_ARRAY, "photo wake produces a multimodal user message")
	if typeof(content) == TYPE_ARRAY:
		var parts := content as Array
		_expect_equal(parts.size(), 2, "photo wake sends one text part and one image part")
		if parts.size() == 2:
			_expect(
				String(((parts[1] as Dictionary).get("image_url", {}) as Dictionary).get("url", ""))
				.begins_with("data:image/png;base64,"),
				"resolved photo bytes enter the model request as image content",
			)
	_expect_equal(
		resolver.calls,
		[{"ref": "chat-photo-37", "mime_type": "image/png"}],
		"prompt compiler resolves each referenced photo once",
	)
	var missing_resolver: RefCounted = compiler_script.new(_initialization())
	_expect_equal(
		missing_resolver.call("compile", wake, "").get("ok"),
		false,
		"photo input fails explicitly when no content resolver is connected",
	)
