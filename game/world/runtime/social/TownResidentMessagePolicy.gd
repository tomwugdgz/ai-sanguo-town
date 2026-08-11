class_name TownResidentMessagePolicy
extends RefCounted


## 居民口信的发送策略。
##
## 消息正文由 TownResidentMessageContent 生成；这里负责选择真实职业居民
## 和把事实口信交给 World 的统一邮递流程。

static func sender_for_source(
	world,
	occupation_id: String,
	source_ref: String,
	excluded_resident_id := "",
	distribution_token := "",
) -> String:
	var candidates: Array[String] = []
	for resident_id: String in world._resident_order:
		if (
			resident_id != excluded_resident_id
			and world._resident_can_work_occupation(resident_id, occupation_id)
		):
			candidates.append(resident_id)
	if candidates.is_empty():
		return ""
	candidates.sort()
	var seed := "%s|%s|%s" % [
		String(source_ref).strip_edges(),
		String(distribution_token).strip_edges(),
		String(excluded_resident_id).strip_edges(),
	]
	var index := posmod(hash(seed), candidates.size())
	return candidates[index]


static func send(world, spec: Dictionary) -> Dictionary:
	var sender_id := String(spec.get("senderResidentId", "")).strip_edges()
	var recipient_id := String(
		spec.get("recipientResidentId", "")
	).strip_edges()
	var content := String(spec.get("content", "")).strip_edges()
	var source_ref := String(spec.get("sourceRef", "")).strip_edges()
	if sender_id.is_empty() or recipient_id.is_empty() or content.is_empty():
		return {
			"ok": false,
			"errorCode": "RESIDENT_MESSAGE_SPEC_INVALID",
			"errors": ["居民口信缺少发送人、收件人或正文"],
		}
	var existing_message := _find_existing_private_message(
		world,
		sender_id,
		recipient_id,
		content,
		source_ref,
	)
	if not existing_message.is_empty():
		return {
			"ok": true,
			"errorCode": "",
			"retryable": false,
			"changed": false,
			"message": world._public_private_message(existing_message),
		}
	return world.create_private_message(
		sender_id,
		recipient_id,
		content,
		"private",
		"",
		int(spec.get("expiresAtMinute", -1)),
		source_ref,
	)


static func _find_existing_private_message(
	world,
	sender_id: String,
	recipient_id: String,
	content: String,
	source_ref: String,
) -> Dictionary:
	var message_ids: Array[String] = []
	for message_id_value: Variant in world._private_messages:
		message_ids.append(String(message_id_value))
	message_ids.sort()
	for message_id: String in message_ids:
		var message := world._private_messages.get(message_id, {}) as Dictionary
		if String(message.get("senderResidentId", "")).strip_edges() != sender_id:
			continue
		if String(message.get("recipientResidentId", "")).strip_edges() != recipient_id:
			continue
		if String(message.get("content", "")).strip_edges() != content:
			continue
		if String(message.get("state", "")) != "pending":
			continue
		if (
			not source_ref.is_empty()
			and String(message.get("sourceRef", "")).strip_edges() != source_ref
		):
			continue
		return message
	return {}
