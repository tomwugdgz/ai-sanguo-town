extends RefCounted


# 世界事件日志的类型/摘要/线索文案纯函数族(O 域迁移第六件)。

static func work_task_log_event_type(state: String, revision: int) -> String:
	match state:
		"open":
			return "工作任务建立" if revision == 1 else "工作任务更新"
		"accepted":
			return "工作任务接取"
		"in_progress":
			return "工作任务进行"
		"waiting":
			return "工作任务等待"
		"completed":
			return "工作任务完成"
		"failed":
			return "工作任务失败"
		"cancelled":
			return "工作任务取消"
	return "工作任务更新"

static func service_log_event_type(service_kind: String) -> String:
	return String({
		"cafe_order": "咖啡交付",
		"dining_order": "供餐完成",
		"grocer_sale": "杂货售卖",
		"flower_sale": "鲜花售卖",
		"clinic": "诊疗结果",
		"clinic_follow_up": "复诊结果",
		"library_checkout": "借书完成",
		"library_return": "还书完成",
		"library_assist": "资料协助",
		"repair": "维修进展",
		"performance": "演出结果",
		"civic_request": "镇务办理",
	}.get(service_kind, "服务结果"))

static func social_matter_log_event_type(state: String, revision: int) -> String:
	match state:
		"latent", "open":
			return "公共事项建立" if revision == 1 else "公共事项更新"
		"collecting":
			return "公共事项征集回应"
		"assigned":
			return "公共事项已分派"
		"executing":
			return "公共事项处理中"
		"closed":
			return "公共事项结束"
	return "公共事项更新"

static func conflict_log_event_type(source_type: String) -> String:
	return String({
		"conflict_challenged": "发生质问",
		"conflict_threatened": "争执升级",
		"conflict_apologized": "争执和解",
		"conflict_disengaged": "主动退让",
		"avatar_area_attack_cast": "化身发动攻击",
		"conflict_formed": "冲突发生",
		"unilateral_hit_confirmed": "攻击确认",
		"injury_applied": "出现受伤",
		"brawl_started": "冲突升级",
		"conflict_intervened": "有人介入",
		"conflict_joined": "有人加入冲突",
		"conflict_left": "有人退出冲突",
		"conflict_ended": "冲突结束",
	}.get(source_type, "冲突变化"))

static func conflict_log_summary(event: Dictionary) -> String:
	var source_type := String(event.get("type", ""))
	if source_type == "injury_applied":
		return (
			"出现重伤"
			if String(event.get("severity", "")) == "heavy"
			else "出现轻伤"
		)
	return String({
		"conflict_challenged": "两位居民发生了当面质问",
		"conflict_threatened": "争执升级为明确威胁",
		"conflict_apologized": "一方道歉，争执没有继续升级",
		"conflict_disengaged": "一方主动离开了争执",
		"avatar_area_attack_cast": "化身的攻击命中了范围内居民",
		"conflict_formed": "冲突已经发生",
		"unilateral_hit_confirmed": "一次攻击已经确认",
		"brawl_started": "冲突升级为持续打斗",
		"conflict_intervened": "第三人介入了冲突",
		"conflict_joined": "新的参与者加入了冲突",
		"conflict_left": "一名参与者退出了冲突",
		"conflict_ended": "冲突已经结束",
	}.get(source_type, "冲突状态发生变化"))

static func conflict_event_actor_ids(event: Dictionary) -> Array[String]:
	var actor_ids: Array[String] = []
	for actor_value: Variant in event.get("actorIds", []) as Array:
		var actor_id := String(actor_value).strip_edges()
		if not actor_id.is_empty() and not actor_ids.has(actor_id):
			actor_ids.append(actor_id)
	for actor_value: Variant in [
		event.get("sourceActorId", ""),
		event.get("subjectId", ""),
	]:
		var actor_id := String(actor_value).strip_edges()
		if not actor_id.is_empty() and not actor_ids.has(actor_id):
			actor_ids.append(actor_id)
	return actor_ids

static func source_text(value: Variant) -> String:
	return (
		String(value).strip_edges()
		if value is String
		else ""
	)

static func initial_social_exposure_clue(
	method: String,
	source_state: Dictionary,
) -> String:
	var place_id := String(source_state.get("place_id", "")).strip_edges()
	if method == "sync_place_service_pressure":
		return "%s里似乎忙不过来。" % place_id
	if method == "sync_animal_attention":
		return "%s附近的小动物引起了动静。" % place_id
	if method == "sync_job_vacancy":
		return "%s的岗位目前空缺。" % place_id
	return "附近似乎发生了一件事。"
