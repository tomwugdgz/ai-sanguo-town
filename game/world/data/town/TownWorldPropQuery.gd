extends RefCounted


const INDOOR_PATH_QUERY := preload(
	"res://world/data/town/TownIndoorPropPathQuery.gd"
)


static func agent_props_at_place(data: Dictionary, place_name: String) -> Array:
	var result := []
	for prop_value in data.get("props", []) as Array:
		var prop := prop_value as Dictionary
		if str(prop.get("placeName", "")) != place_name:
			continue
		if prop.get("agentVisible", true) == false:
			continue
		var verbs := PackedStringArray()
		for action_value in prop.get("actions", []) as Array:
			var verb := str((action_value as Dictionary).get("verb", ""))
			if not verb.is_empty():
				verbs.append(verb)
		verbs.sort()
		var verb_values := []
		for verb in verbs:
			verb_values.append(str(verb))
		result.append({
			"name": str(prop.get("name", "")),
			"verbs": verb_values,
		})
	result.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		return str(left.get("name", "")) < str(right.get("name", ""))
	)
	return result


static func action_definition(
	data: Dictionary,
	place_name: String,
	prop_name: String,
	verb: String
) -> Dictionary:
	for prop_value in data.get("props", []) as Array:
		var prop := prop_value as Dictionary
		if (
			str(prop.get("placeName", "")) != place_name
			or str(prop.get("name", "")) != prop_name
		):
			continue
		for action_value in prop.get("actions", []) as Array:
			var action := action_value as Dictionary
			if str(action.get("verb", "")) == verb:
				var normalized_effects := {}
				for state_value in (action.get("effects", {}) as Dictionary):
					normalized_effects[str(state_value)] = int(
						(action.get("effects", {}) as Dictionary)[state_value]
					)
				return {
					"durationMinutes": int(action.get("durationMinutes", 0)),
					"effects": normalized_effects,
				}
	return {}


static func interaction_plan(
	data: Dictionary,
	place_name: String,
	prop_name: String,
	verb: String,
	start_position: Variant = null,
) -> Dictionary:
	var action := action_definition(data, place_name, prop_name, verb)
	if action.is_empty():
		return {}
	for prop_value in data.get("props", []) as Array:
		var prop := prop_value as Dictionary
		if (
			str(prop.get("placeName", "")) != place_name
			or str(prop.get("name", "")) != prop_name
		):
			continue
		var interaction := prop.get("interaction", {}) as Dictionary
		var position_values := interaction.get("position", []) as Array
		if position_values.size() != 2:
			return {}
		var space_id := str(interaction.get("spaceId", ""))
		var target_position := Vector2(float(position_values[0]), float(position_values[1]))
		var points: Array[Vector2] = []
		if space_id == "town_outdoor":
			var polyline_values := interaction.get("approachPolyline", []) as Array
			if polyline_values.size() < 2:
				return {}
			for point_value: Variant in polyline_values:
				var pair := point_value as Array
				points.append(Vector2(float(pair[0]), float(pair[1])))
		else:
			if not start_position is Vector2:
				return {}
			var navigation := _indoor_navigation(data, space_id)
			points = INDOOR_PATH_QUERY.find_path(
				navigation,
				start_position as Vector2,
				target_position,
			)
			if points.is_empty():
				return {}
		return {
			"propId": str(prop.get("id", "")),
			"propName": prop_name,
			"verb": verb,
			"placeName": place_name,
			"spaceId": space_id,
			"regionId": str(interaction.get("regionId", "")),
			"position": target_position,
			"approachPolyline": points,
			"durationMinutes": int(action.get("durationMinutes", 0)),
			"effects": (action.get("effects", {}) as Dictionary).duplicate(true),
		}
	return {}


static func presentation_cue(
	data: Dictionary,
	place_name: String,
	prop_name: String,
	verb: String,
) -> Dictionary:
	if action_definition(data, place_name, prop_name, verb).is_empty():
		return {}
	for prop_value in data.get("props", []) as Array:
		var prop := prop_value as Dictionary
		if (
			str(prop.get("placeName", "")) != place_name
			or str(prop.get("name", "")) != prop_name
		):
			continue
		var interaction := prop.get("interaction", {}) as Dictionary
		return {
			"actionType": "用道具",
			"propId": str(prop.get("id", "")),
			"prop": prop_name,
			"verb": verb,
			"anchorKind": str(interaction.get("anchorKind", "")),
			"actorFacing": _actor_facing(interaction),
			"instanceId": str(interaction.get("instanceId", "")),
			"assetId": str(interaction.get("assetId", "")),
			"instancePosition": interaction.get("instancePosition"),
			"direction": str(interaction.get("direction", "")),
		}
	return {}


static func _actor_facing(interaction: Dictionary) -> String:
	var authored := str(interaction.get("actorFacing", ""))
	if authored in ["down", "right", "up", "left"]:
		return authored
	var points := interaction.get("approachPolyline", []) as Array
	if points.size() < 2:
		return ""
	var before := points[-2] as Array
	var target := points[-1] as Array
	if before.size() != 2 or target.size() != 2:
		return ""
	var direction := Vector2(
		float(target[0]) - float(before[0]),
		float(target[1]) - float(before[1]),
	)
	if direction.length_squared() <= 0.001:
		return ""
	if absf(direction.x) > absf(direction.y):
		return "right" if direction.x > 0.0 else "left"
	return "down" if direction.y > 0.0 else "up"


static func _indoor_navigation(data: Dictionary, space_id: String) -> Dictionary:
	for value: Variant in data.get("indoorNavigation", []) as Array:
		var navigation := value as Dictionary
		if str(navigation.get("spaceId", "")) == space_id:
			return navigation
	return {}
