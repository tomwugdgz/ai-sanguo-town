extends RefCounted


# O 域迁移首件(F 之 3 模式证明):动作时序两函数,依赖面仅环境时钟。
# world 参数式静态,与感知模块同模式。

static func rebase_action_timing(world, action: Dictionary) -> void:
	var now := int(world.environment().get_absolute_minute())
	var previous_start := int(action.get("startedAbsoluteMinute", now))
	action["startedAbsoluteMinute"] = now
	if String(action.get("type", "")) == "待着":
		var previous_end := int(action.get("completeAbsoluteMinute", previous_start + 1))
		action["completeAbsoluteMinute"] = now + maxi(1, previous_end - previous_start)


static func resume_suspended_action(world, resident: Dictionary) -> void:
	var suspended_at := int(resident.get("actionSuspendedAbsoluteMinute", -1))
	var action := resident.get("currentAction", {}) as Dictionary
	if suspended_at >= 0 and not action.is_empty():
		var now := int(world.environment().get_absolute_minute())
		var elapsed := maxi(0, now - suspended_at)
		if action.has("startedAbsoluteMinute"):
			action["startedAbsoluteMinute"] = int(action.get("startedAbsoluteMinute", now)) + elapsed
		if action.has("completeAbsoluteMinute"):
			action["completeAbsoluteMinute"] = int(action.get("completeAbsoluteMinute", now)) + elapsed
		resident["currentAction"] = action
	resident["actionSuspendedAbsoluteMinute"] = -1
