extends RefCounted

# 空间视图同步协调器（自 TownRuntime 拆出，纯表现层，不碰世界运行时）。
#
# 背景：居民表现层按"激活空间"门控——不在激活空间的 body 会被
# set_space_active(false) 冻结本地推进，但世界时间照常走。一旦
# 表现层激活空间与玩家实际看见的空间失配（例如 UI 流程中途切了视角、
# 传送退出被守卫提前返回），就会出现"人物原地不动、世界已经走远"。
#
# 本模块提供两个能力：
# - desired_space：从 TownRuntime 的实际可视状态推导期望空间。
#   不信任可能被 UI 流程改写的 _observed_place_name，优先走 portal 映射。
# - reconcile：对比表现层激活空间与期望空间，不一致即重同步
#   （set_active_space 内部会 force relocate + 重新激活物理）。
#   由黑屏传送钩子（预热）和 TownRuntime 周期兜底共同调用，幂等。

static func desired_space(town) -> Dictionary:
	if town == null or not town.has_method("_is_inside_interior"):
		return {}
	if not town._is_inside_interior():
		return {
			"outdoor": true,
			"placeName": "",
			"origin": Vector2.ZERO,
		}
	var interior_id := String(town._active_interior_id)
	var room := town._interior_roots.get(interior_id) as Node2D
	if room == null or not room.visible:
		# 记录上还在室内，但房间实际不可见——以可见性为准。
		return {
			"outdoor": true,
			"placeName": "",
			"origin": Vector2.ZERO,
		}
	var place_name := String(
		town._place_name_for_portal_id(String(town._active_exterior_portal_id)),
	)
	if place_name.is_empty():
		place_name = String(town._observed_place_name)
	if place_name.is_empty():
		# 判定不出当前房间对应的地点，本拍不动，等下一拍。
		return {}
	return {
		"outdoor": false,
		"placeName": place_name,
		"origin": room.position,
	}


static func reconcile(town, presentation, reason := "") -> Dictionary:
	if town == null or presentation == null:
		return {"ok": false, "changed": false, "reason": reason}
	var desired := desired_space(town)
	if desired.is_empty():
		return {"ok": true, "changed": false, "skipped": true, "reason": reason}
	var desired_space_id := "town_outdoor"
	if not bool(desired.get("outdoor", true)):
		var world: Variant = town._world
		if world == null or not world.has_method("get_place_detail"):
			return {"ok": false, "changed": false, "reason": reason}
		var place_value: Variant = world.get_place_detail(
			String(desired.get("placeName", "")),
		)
		if place_value is not Dictionary:
			return {"ok": false, "changed": false, "reason": reason}
		desired_space_id = String(
			(place_value as Dictionary).get("spaceId", ""),
		)
		if desired_space_id.is_empty():
			return {"ok": false, "changed": false, "reason": reason}
	if String(presentation.get_active_space_id()) == desired_space_id:
		return {
			"ok": true,
			"changed": false,
			"reason": reason,
			"spaceId": desired_space_id,
		}
	var result: Dictionary
	if bool(desired.get("outdoor", true)):
		result = presentation.clear_observed_interior() as Dictionary
	else:
		result = presentation.set_observed_interior(
			String(desired.get("placeName", "")),
			desired.get("origin", Vector2.ZERO) as Vector2,
		) as Dictionary
	result["changed"] = true
	result["reason"] = reason
	return result
