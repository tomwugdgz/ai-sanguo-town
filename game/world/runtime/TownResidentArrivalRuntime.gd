class_name TownResidentArrivalRuntime
extends RefCounted


const CHARACTER_MOVEMENT_QUERY := preload(
	"res://world/data/town/TownWorldCharacterMovementQuery.gd"
)
const ROUTE_QUERY := preload("res://world/data/town/TownWorldRouteQuery.gd")
const SOUTH_ENTRY_PLACE := "南入口"
const ENTRY_CONTINUITY_LINES: Array[String] = [
	"刚到镇上，先慢慢往里走几步看看四周",
	"沿着入口往里走，先熟悉一下周围",
	"先离开入口，到前面看看镇上的早晨",
]

static var _arrival_safe_position_cache: Dictionary = {}
static var _arrival_home_route_cache: Dictionary = {}
static var _arrival_entry_state_cache: Dictionary = {}


static func clear_cache() -> void:
	_arrival_safe_position_cache.clear()
	_arrival_home_route_cache.clear()
	_arrival_entry_state_cache.clear()


static func activate_entry_continuity(
	world,
	resident_id: String,
	resident: Dictionary,
	absolute_minute: int,
) -> void:
	var action_id := "%s-arrival-%d" % [resident_id, absolute_minute]
	var line := ENTRY_CONTINUITY_LINES[
		posmod(hash(resident_id), ENTRY_CONTINUITY_LINES.size())
	]
	var action := {
		"action_id": action_id,
		"type": "待着",
		"line": line,
		"startedAbsoluteMinute": absolute_minute,
		"completeAbsoluteMinute": absolute_minute + 2,
		"decisionBridge": true,
	}
	var home := String(
		(resident.get("socialState", {}) as Dictionary).get("home", ""),
	).strip_edges()
	if not home.is_empty():
		var route := ROUTE_QUERY.find_route_from_state(
			world.world_data(),
			{
				"position": resident.get("position", Vector2.ZERO),
				"spaceId": resident.get("spaceId", ""),
				"regionId": resident.get("regionId", ""),
				"currentPlace": resident.get("currentPlace", ""),
			},
			home,
			resident.get("routeConnector", []) as Array,
		) as Dictionary
		var step_path := _first_route_step_path(route)
		if step_path.size() >= 2:
			action["idlePathPoints"] = step_path
			action["idleTargetPosition"] = step_path[-1]
			action["idleMoveDurationMinutes"] = 1
	resident["currentAction"] = action
	resident["actionSuspendedAbsoluteMinute"] = -1
	resident["doing"] = line


static func _first_route_step_path(route: Dictionary) -> Array[Vector2]:
	var result: Array[Vector2] = []
	var samples := route.get("minutePositions", []) as Array
	if samples.size() < 2 or not samples[1] is Dictionary:
		return result
	for point_value: Variant in (samples[1] as Dictionary).get(
		"presentationPath",
		[],
	) as Array:
		if not point_value is Dictionary:
			return []
		var point := point_value as Dictionary
		result.append(Vector2(
			float(point.get("x", 0.0)),
			float(point.get("y", 0.0)),
		))
	return result


static func is_entry_continuity_action_id(
	resident_id: String,
	action_id: String,
) -> bool:
	return action_id.begins_with("%s-arrival-" % resident_id)


static func prewarm_pending_entry_states(world, clearance_px: float) -> void:
	var residents := world.residents() as Dictionary
	for resident_id: String in world.resident_order():
		var resident := residents.get(resident_id, {}) as Dictionary
		var arrival_state := resident.get("arrivalState", {}) as Dictionary
		if String(arrival_state.get("status", "")) != "pending":
			continue
		entry_state_for(world, resident_id, clearance_px)


static func entry_state_for(
	world,
	resident_id: String,
	clearance_px: float,
) -> Dictionary:
	var residents := world.residents() as Dictionary
	var resident := residents.get(resident_id, {}) as Dictionary
	var entry_cache_key := "%s|%.3f" % [resident_id, clearance_px]
	if _arrival_entry_state_cache.has(entry_cache_key):
		var cached_entry := _arrival_entry_state_cache[entry_cache_key] as Dictionary
		var cached_position := cached_entry.get("position", Vector2.INF) as Vector2
		var occupied_cached: Array[Vector2] = []
		for other_id: String in world.resident_order():
			if other_id == resident_id:
				continue
			var other := residents.get(other_id, {}) as Dictionary
			if (
				not world.resident_is_present(other)
				or String(other.get("spaceId", "")) != "town_outdoor"
			):
				continue
			var other_position := other.get("position", Vector2.INF) as Vector2
			if other_position.is_finite():
				occupied_cached.append(other_position)
		if (
			not cached_entry.is_empty()
			and cached_position.is_finite()
			and not world._point_near_any(cached_position, occupied_cached, clearance_px)
		):
			return cached_entry.duplicate(true)
		_arrival_entry_state_cache.erase(entry_cache_key)
	var preferred := resident.get("position", Vector2.ZERO) as Vector2
	var occupied: Array[Vector2] = []
	for other_id: String in world.resident_order():
		if other_id == resident_id:
			continue
		var other := residents.get(other_id, {}) as Dictionary
		if (
			not world.resident_is_present(other)
			or String(other.get("spaceId", "")) != "town_outdoor"
		):
			continue
		var position := other.get("position", Vector2.INF) as Vector2
		if position.is_finite():
			occupied.append(position)
	var candidate_offsets: Array[Vector2] = [Vector2.ZERO]
	var direction_offset := posmod(hash(resident_id), 16)
	for ring_radius in [64.0, 128.0, 192.0]:
		for direction_index in 16:
			var angle := TAU * float(
				posmod(direction_index + direction_offset, 16),
			) / 16.0
			candidate_offsets.append(
				Vector2(cos(angle), sin(angle)) * ring_radius,
			)
	var reach_cache := {}
	var candidate_checks := 0
	for offset in candidate_offsets:
		if candidate_checks >= 8:
			break
		candidate_checks += 1
		var requested_position := preferred + offset
		var cache_key := "town_outdoor|%.3f|%.3f" % [
			requested_position.x,
			requested_position.y,
		]
		var resolved: Dictionary
		if _arrival_safe_position_cache.has(cache_key):
			resolved = _arrival_safe_position_cache[cache_key] as Dictionary
		else:
			resolved = CHARACTER_MOVEMENT_QUERY.nearest_safe_position(
				world.world_data(),
				"town_outdoor",
				requested_position,
			) as Dictionary
			_arrival_safe_position_cache[cache_key] = resolved.duplicate(true)
		if (
			resolved.is_empty()
			or String(resolved.get("placeName", "")) != SOUTH_ENTRY_PLACE
		):
			continue
		var position := resolved.get("position", Vector2.INF) as Vector2
		if not position.is_finite():
			continue
		var reach_key := "%s|%s|%.3f|%.3f" % [
			String(resolved.get("spaceId", "")),
			String(resolved.get("regionId", "")),
			position.x,
			position.y,
		]
		if not reach_cache.has(reach_key):
			reach_cache[reach_key] = _can_reach_home(
				world,
				resident,
				resolved,
			)
		if (
			bool(reach_cache[reach_key])
			and not world._point_near_any(position, occupied, clearance_px)
		):
			_arrival_entry_state_cache[entry_cache_key] = resolved.duplicate(true)
			return resolved
	var fallback := CHARACTER_MOVEMENT_QUERY.nearest_safe_position(
		world.world_data(),
		"town_outdoor",
		preferred,
	) as Dictionary
	_arrival_entry_state_cache[entry_cache_key] = fallback.duplicate(true)
	return fallback


static func _can_reach_home(
	world,
	resident: Dictionary,
	entry_state: Dictionary,
) -> bool:
	var home := String(
		(resident.get("socialState", {}) as Dictionary).get("home", ""),
	).strip_edges()
	if home.is_empty():
		return true
	var position := entry_state.get("position", Vector2.ZERO) as Vector2
	var cache_key := "%s|%s|%s|%.3f|%.3f" % [
		home,
		String(entry_state.get("spaceId", "")),
		String(entry_state.get("regionId", "")),
		position.x,
		position.y,
	]
	if _arrival_home_route_cache.has(cache_key):
		return bool(_arrival_home_route_cache[cache_key])
	var reachable := not ROUTE_QUERY.find_route_from_state(
		world.world_data(),
		{
			"position": position,
			"spaceId": entry_state.get("spaceId", ""),
			"regionId": entry_state.get("regionId", ""),
			"currentPlace": entry_state.get("placeName", ""),
		},
		home,
	).is_empty()
	_arrival_home_route_cache[cache_key] = reachable
	return reachable
