extends RefCounted


const MOVEMENT_NETWORK_PATH := "res://world/data/town/source/movement_network.json"

var _nodes_by_id: Dictionary = {}
var _edges_by_pair: Dictionary = {}


func load_catalog() -> bool:
	_nodes_by_id.clear()
	_edges_by_pair.clear()
	if not FileAccess.file_exists(MOVEMENT_NETWORK_PATH):
		push_error("主菜单氛围路线缺少正式移动网络：%s" % MOVEMENT_NETWORK_PATH)
		return false
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(MOVEMENT_NETWORK_PATH))
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("主菜单氛围路线无法解析正式移动网络")
		return false
	var document := parsed as Dictionary
	for node_value: Variant in document.get("nodes", []) as Array:
		if typeof(node_value) != TYPE_DICTIONARY:
			continue
		var node := node_value as Dictionary
		var node_id := String(node.get("id", ""))
		if not node_id.is_empty():
			_nodes_by_id[node_id] = node
	for edge_value: Variant in document.get("edges", []) as Array:
		if typeof(edge_value) != TYPE_DICTIONARY:
			continue
		var edge := edge_value as Dictionary
		var from_id := String(edge.get("fromNodeId", ""))
		var to_id := String(edge.get("toNodeId", ""))
		if from_id.is_empty() or to_id.is_empty():
			continue
		_edges_by_pair[_edge_key(from_id, to_id)] = edge
	return not _nodes_by_id.is_empty() and not _edges_by_pair.is_empty()


func build_loop_script(
	node_ids: PackedStringArray,
	indoor_stops: Dictionary
) -> Array[Dictionary]:
	var steps: Array[Dictionary] = []
	if node_ids.size() < 2 or node_ids[0] != node_ids[-1]:
		push_error("主菜单氛围路线必须首尾闭合")
		return steps
	for index in range(1, node_ids.size()):
		var from_id := node_ids[index - 1]
		var to_id := node_ids[index]
		var edge := _edges_by_pair.get(_edge_key(from_id, to_id), {}) as Dictionary
		if edge.is_empty():
			push_error("主菜单氛围路线缺少正式路段：%s -> %s" % [from_id, to_id])
			return []
		var points := _edge_points(edge, from_id)
		if points.size() < 2:
			push_error("主菜单氛围路段折线无效：%s -> %s" % [from_id, to_id])
			return []
		steps.append({"type": "move", "points": points})
		if indoor_stops.has(to_id):
			var wait_range: Vector2 = indoor_stops[to_id]
			steps.append({
				"type": "enter",
				"door": points[-1],
				"wait_min": minf(wait_range.x, wait_range.y),
				"wait_max": maxf(wait_range.x, wait_range.y),
			})
	return steps


func _edge_points(edge: Dictionary, requested_from_id: String) -> PackedVector2Array:
	var points := PackedVector2Array()
	for point_value: Variant in edge.get("polyline", []) as Array:
		if typeof(point_value) != TYPE_DICTIONARY:
			continue
		var point := point_value as Dictionary
		points.append(Vector2(
			float(point.get("x", 0.0)),
			float(point.get("y", 0.0)),
		))
	if String(edge.get("fromNodeId", "")) != requested_from_id:
		points.reverse()
	return points


func _edge_key(left_id: String, right_id: String) -> String:
	if left_id.naturalnocasecmp_to(right_id) <= 0:
		return "%s|%s" % [left_id, right_id]
	return "%s|%s" % [right_id, left_id]
