extends RefCounted


# 社会事项判定纯函数族(O 域迁移第七件甲)。

const CONTENT_CATALOG := preload(
	"res://world/data/town/TownWorkContentCatalog.gd"
)
const BULLETIN_PUBLISH_ACTIVITY_ID := "activity_bulletin_publish"
const BULLETIN_READ_ACTIVITY_ID := "activity_bulletin_read"
const COMMUNITY_BULLETIN_PLACE_ID := CONTENT_CATALOG.PLACE_PLAZA

static func social_resident_already_considered(
	matter: Dictionary,
	resident_id: String,
) -> bool:
	for round_value: Variant in matter.get(
		"response_history",
		[],
	) as Array:
		if not round_value is Dictionary:
			continue
		for candidate_value: Variant in (
			(round_value as Dictionary).get(
				"fixed_candidates",
				[],
			) as Array
		):
			if (
				candidate_value is Dictionary
				and bool(
					(candidate_value as Dictionary).get(
						"terminal",
						false,
					)
				)
				and String(
					(candidate_value as Dictionary).get(
						"resident_id",
						"",
					)
				) == resident_id
			):
				return true
	return false

static func social_goal_action_type_matches(
	action_goal: Dictionary,
	action: Dictionary,
) -> bool:
	var capability_id := String(action_goal.get("capability_id", ""))
	if capability_id in ["world.escort_person_to_place", "world.fetch_service_for_person"]:
		return (
			not String(action.get("conversationFollowUpMode", "")).is_empty()
			and String(action.get("type", "")) in ["去", "待着", "搭话"]
		)
	var expected_type := String({
		"world.go_to_place": "去",
		"world.start_conversation": "搭话",
		"world.reply_conversation": "答话",
		"world.wait": "待着",
	}.get(capability_id, ""))
	return (
		not expected_type.is_empty()
		and String(action.get("type", "")) == expected_type
	)

static func social_goal_matches_activity(
	action_goal: Dictionary,
	execution: Dictionary,
) -> bool:
	var capability_id := String(action_goal.get("capability_id", ""))
	if capability_id == "bulletin.read":
		return (
			String(execution.get("activityId", ""))
			== BULLETIN_READ_ACTIVITY_ID
			and String(execution.get("placeId", ""))
			== COMMUNITY_BULLETIN_PLACE_ID
		)
	if capability_id == "bulletin.publish":
		return (
			String(execution.get("activityId", ""))
			== BULLETIN_PUBLISH_ACTIVITY_ID
			and String(execution.get("placeId", ""))
			== COMMUNITY_BULLETIN_PLACE_ID
		)
	if capability_id != "world.perform_activity":
		return false
	var target_refs := action_goal.get("target_refs", {}) as Dictionary
	return (
		String(execution.get("activityId", ""))
		== String(target_refs.get("activity_id", ""))
		and String(execution.get("placeId", ""))
		== String(target_refs.get("place_id", ""))
	)

static func matter_has_active_social_participants(matter: Dictionary) -> bool:
	for participant_value: Variant in (
		matter.get("participants", {}) as Dictionary
	).values():
		if String((participant_value as Dictionary).get("status", "")) in [
			"assigned",
			"executing",
		]:
			return true
	return false

static func social_execution_status(status: String) -> String:
	if status == "completed":
		return "completed"
	if status in ["interrupted", "replaced"]:
		return "interrupted"
	return "failed"


static func resident_social_available_at(world, 
	resident_id: String,
	now: int,
) -> int:
	var resident := world.residents().get(resident_id, {}) as Dictionary
	var action := resident.get("currentAction", {}) as Dictionary
	if action.is_empty():
		return now
	return maxi(
		now,
		int(action.get("completeAbsoluteMinute", now)),
	)
