class_name TownPortalCatalog
extends RefCounted


# 玩家与居民共同使用的室外门台账。door 是真实门槛；return 是出门后的
# 安全落点。室内入口与房间布局仍由室内数据负责。
const DOOR_THRESHOLD_TRIGGER_SIZE := Vector2(64.0, 14.0)
const EXTERIOR_INTERIOR_PORTALS: Array[Dictionary] = [
	{"id": "cafe", "interior_id": "cafe", "node_name": "CafeDoorAutoPortal", "door": Vector2(4378.0, 3209.0), "return": Vector2(4378.0, 3415.0), "size": Vector2(110.0, 90.0)},
	{"id": "library", "interior_id": "library", "node_name": "LibraryDoorAutoPortal", "door": Vector2(2070.0, 815.0), "return": Vector2(2070.0, 950.0), "size": Vector2(110.0, 90.0)},
	{"id": "town_hall", "interior_id": "town_hall", "node_name": "TownHallDoorAutoPortal", "door": Vector2(3140.0, 1081.0), "return": Vector2(3140.0, 1230.0), "size": Vector2(120.0, 90.0)},
	{"id": "clinic", "interior_id": "clinic", "node_name": "ClinicDoorAutoPortal", "door": Vector2(4225.0, 1120.0), "return": Vector2(4225.0, 1260.0), "size": Vector2(110.0, 90.0)},
	{"id": "market", "interior_id": "market", "node_name": "MarketDoorAutoPortal", "door": Vector2(3980.0, 2013.0), "return": Vector2(3980.0, 2160.0), "size": Vector2(110.0, 90.0)},
	{"id": "dining_hall", "interior_id": "dining_hall", "node_name": "DiningHallDoorAutoPortal", "door": Vector2(4755.0, 1929.0), "return": Vector2(4755.0, 2035.0), "size": Vector2(110.0, 90.0)},
	{"id": "workshop", "interior_id": "workshop", "node_name": "WorkshopDoorAutoPortal", "door": Vector2(5000.0, 2627.0), "return": Vector2(5000.0, 2760.0), "size": Vector2(110.0, 90.0)},
	{"id": "dock_warehouse", "interior_id": "dock_warehouse", "node_name": "DockWarehouseDoorAutoPortal", "door": Vector2(6050.0, 2901.0), "return": Vector2(6050.0, 3071.0), "size": Vector2(130.0, 100.0)},
	{"id": "home_01", "interior_id": "home_a", "node_name": "Home01DoorAutoPortal", "door": Vector2(2595.0, 560.0), "return": Vector2(2595.0, 675.0), "size": Vector2(100.0, 85.0)},
	{"id": "home_02", "interior_id": "home_b", "node_name": "Home02DoorAutoPortal", "door": Vector2(3230.0, 606.0), "return": Vector2(3230.0, 690.0), "size": Vector2(100.0, 85.0)},
	{"id": "home_03", "interior_id": "home_b", "node_name": "Home03DoorAutoPortal", "door": Vector2(4005.0, 586.0), "return": Vector2(4005.0, 680.0), "size": Vector2(100.0, 85.0)},
	{"id": "home_04", "interior_id": "home_b", "node_name": "Home04DoorAutoPortal", "door": Vector2(520.0, 1847.0), "return": Vector2(520.0, 1910.0), "size": Vector2(100.0, 85.0)},
	{"id": "home_05", "interior_id": "home_a", "node_name": "Home05DoorAutoPortal", "door": Vector2(1630.0, 1721.0), "return": Vector2(1630.0, 1820.0), "size": Vector2(100.0, 85.0)},
	{"id": "home_06", "interior_id": "home_b", "node_name": "Home06DoorAutoPortal", "door": Vector2(2245.0, 1754.0), "return": Vector2(2245.0, 1882.0), "size": Vector2(100.0, 85.0)},
	{"id": "home_07", "interior_id": "home_b", "node_name": "Home07DoorAutoPortal", "door": Vector2(1320.0, 2374.0), "return": Vector2(1320.0, 2460.0), "size": Vector2(100.0, 85.0)},
	{"id": "home_08", "interior_id": "home_b", "node_name": "Home08DoorAutoPortal", "door": Vector2(2115.0, 2361.0), "return": Vector2(2115.0, 2475.0), "size": Vector2(100.0, 85.0)},
	{"id": "home_09", "interior_id": "home_a", "node_name": "Home09DoorAutoPortal", "door": Vector2(1695.0, 2956.0), "return": Vector2(1695.0, 3030.0), "size": Vector2(100.0, 85.0)},
	{"id": "home_10", "interior_id": "home_b", "node_name": "Home10DoorAutoPortal", "door": Vector2(2295.0, 2967.0), "return": Vector2(2295.0, 3100.0), "size": Vector2(100.0, 85.0)},
	{"id": "home_11", "interior_id": "home_a", "node_name": "Home11DoorAutoPortal", "door": Vector2(2215.0, 3420.0), "return": Vector2(2215.0, 3545.0), "size": Vector2(100.0, 85.0)},
	{"id": "home_12", "interior_id": "home_a", "node_name": "Home12DoorAutoPortal", "door": Vector2(2865.0, 3416.0), "return": Vector2(2865.0, 3565.0), "size": Vector2(100.0, 85.0)},
	{"id": "home_13", "interior_id": "home_a", "node_name": "Home13DoorAutoPortal", "door": Vector2(3655.0, 3447.0), "return": Vector2(3655.0, 3570.0), "size": Vector2(100.0, 85.0)},
	{"id": "home_14", "interior_id": "home_a", "node_name": "Home14DoorAutoPortal", "door": Vector2(4240.0, 2630.0), "return": Vector2(4240.0, 2730.0), "size": Vector2(100.0, 85.0)},
	{"id": "home_15", "interior_id": "home_a", "node_name": "Home15DoorAutoPortal", "door": Vector2(835.0, 1429.0), "return": Vector2(835.0, 1580.0), "size": Vector2(100.0, 85.0)},
]


static func definition(portal_id: String) -> Dictionary:
	var canonical_id := portal_id.trim_prefix("portal_")
	if canonical_id == "market_shop":
		canonical_id = "market"
	for value: Dictionary in EXTERIOR_INTERIOR_PORTALS:
		if String(value.get("id", "")) == canonical_id:
			return value
	return {}


static func threshold_size(portal: Dictionary) -> Vector2:
	var authored_size := portal.get(
		"size",
		DOOR_THRESHOLD_TRIGGER_SIZE,
	) as Vector2
	return Vector2(
		authored_size.x,
		DOOR_THRESHOLD_TRIGGER_SIZE.y,
	)


static func exterior_trigger_rect(portal: Dictionary) -> Rect2:
	if portal.is_empty():
		return Rect2()
	var door := portal.get("door", Vector2.INF) as Vector2
	var size := threshold_size(portal)
	if not door.is_finite() or size.x <= 0.0 or size.y <= 0.0:
		return Rect2()
	return Rect2(door - size * 0.5, size)
