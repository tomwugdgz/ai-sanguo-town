extends RefCounted


const MOVEMENT := preload(
	"res://world/data/town/TownWorldCharacterMovementQuery.gd"
)


static func with_authoritative_outdoor_spawns(
	world_data: Dictionary,
	opening_config: Dictionary,
) -> Dictionary:
	return with_authoritative_new_game_spawns(world_data, opening_config)


static func with_authoritative_new_game_spawns(
	world_data: Dictionary,
	opening_config: Dictionary,
) -> Dictionary:
	var result := opening_config.duplicate(true)
	var south_entry := MOVEMENT.formal_south_entry(world_data) as Dictionary
	var south_position := south_entry.get("position", Vector2.ZERO) as Vector2
	for resident_value: Variant in result.get("residents", []) as Array:
		var resident := resident_value as Dictionary
		var state := resident.get("worldState", {}) as Dictionary
		state["place"] = String(south_entry.get("placeName", ""))
		state["spaceId"] = String(south_entry.get("spaceId", ""))
		state["regionId"] = String(south_entry.get("regionId", ""))
		state["position"] = [south_position.x, south_position.y]
	return result
