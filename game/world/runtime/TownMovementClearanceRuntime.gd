class_name TownMovementClearanceRuntime
extends RefCounted


const CHARACTER_MOVEMENT_QUERY := preload(
	"res://world/data/town/TownWorldCharacterMovementQuery.gd"
)
const MAX_CACHE_ENTRIES := 4096

static var _safe_position_cache: Dictionary = {}
static var _cache_order: Array[String] = []


static func clear_cache() -> void:
	_safe_position_cache.clear()
	_cache_order.clear()


static func nearest_safe_position(
	world_data: Dictionary,
	space_id: String,
	position: Vector2,
) -> Vector2:
	if not position.is_finite():
		return position
	var cache_key := "%s|%.3f|%.3f" % [space_id, position.x, position.y]
	if _safe_position_cache.has(cache_key):
		return _safe_position_cache[cache_key] as Vector2
	var resolved := CHARACTER_MOVEMENT_QUERY.nearest_safe_position(
		world_data,
		space_id,
		position,
	) as Dictionary
	var safe_position := position
	if not resolved.is_empty():
		safe_position = resolved.get("position", position) as Vector2
	_safe_position_cache[cache_key] = safe_position
	_cache_order.append(cache_key)
	if _cache_order.size() > MAX_CACHE_ENTRIES:
		_safe_position_cache.erase(_cache_order.pop_front())
	return safe_position
