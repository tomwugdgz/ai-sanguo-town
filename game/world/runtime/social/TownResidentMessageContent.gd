class_name TownResidentMessageContent
extends RefCounted


## 事实口信的正文和关联来源。
##
## 这个模块不创建消息、不选择邮递人，只把已经确认的事实转成玩家能看懂
## 的居民话。投递和职业选择由 TownResidentMessagePolicy 处理。

static func civic_completion(
	sender_id: String,
	recipient_id: String,
	request_id := "",
) -> Dictionary:
	return _private(
		sender_id,
		recipient_id,
		"你提交的镇务已经处理好了。",
		"civic-request:%s" % request_id if not request_id.is_empty() else "",
	)


static func performance_invitation(
	sender_id: String,
	recipient_id: String,
	day_index: int,
	expires_at_minute: int,
) -> Dictionary:
	return _private(
		sender_id,
		recipient_id,
		"我准备在中心广场演奏，有空可以来听。",
		"performance-event:%d" % day_index,
		expires_at_minute,
	)


static func announcement_notice(
	sender_id: String,
	recipient_id: String,
	announcement_text: String,
	announcement_id: String,
	expires_at_minute: int = -1,
) -> Dictionary:
	var normalized_announcement_id := announcement_id.strip_edges()
	return _private(
		sender_id,
		recipient_id,
		announcement_text,
		"announcement-notice:%s" % normalized_announcement_id,
		expires_at_minute,
	)


static func preorder_ready(
	sender_id: String,
	recipient_id: String,
	place_id: String,
	request_id: String,
	expires_at_minute: int,
) -> Dictionary:
	return _private(
		sender_id,
		recipient_id,
		"你预订的东西已经到了，有空请来%s取。" % place_id,
		"preorder:%s" % request_id,
		expires_at_minute,
	)


static func repair_ready(
	sender_id: String,
	recipient_id: String,
	request_id: String,
	expires_at_minute: int,
) -> Dictionary:
	return _private(
		sender_id,
		recipient_id,
		"你的东西已经修好了，有空请来工作坊成品架领取。",
		"repair-pickup:%s" % request_id,
		expires_at_minute,
	)


static func library_due(
	sender_id: String,
	recipient_id: String,
	loan_id: String,
	expires_at_minute: int,
) -> Dictionary:
	return _private(
		sender_id,
		recipient_id,
		"你借的书到归还时间了，有空请带回图书馆。",
		"library-return:%s" % loan_id,
		expires_at_minute,
	)


static func clinic_follow_up(
	sender_id: String,
	recipient_id: String,
	complaint: String,
	follow_up_id: String,
	expires_at_minute: int,
) -> Dictionary:
	var detail := complaint.strip_edges()
	var detail_text := ""
	if not detail.is_empty():
		detail_text = "（%s）" % detail
	return _private(
		sender_id,
		recipient_id,
		"复诊时间到了，记得来诊所复查%s。" % detail_text,
		"clinic-follow-up:%s" % follow_up_id,
		expires_at_minute,
	)


static func research_accessioned(
	sender_id: String,
	recipient_id: String,
	record_id: String,
) -> Dictionary:
	return _private(
		sender_id,
		recipient_id,
		"你的研究记录已经入藏图书馆了，有空可以来查阅。",
		"research-accession:%s" % record_id,
	)


static func _private(
	sender_id: String,
	recipient_id: String,
	content: String,
	source_ref: String,
	expires_at_minute := -1,
) -> Dictionary:
	return {
		"senderResidentId": sender_id,
		"recipientResidentId": recipient_id,
		"content": content,
		"sourceRef": source_ref,
		"expiresAtMinute": expires_at_minute,
	}
