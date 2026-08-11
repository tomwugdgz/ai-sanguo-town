class_name AiTownUiNodeRetirement
extends RefCounted


static func retire(node: Node) -> bool:
	if node == null or not is_instance_valid(node) or node.is_queued_for_deletion():
		return false
	# A control can request a rebuild from inside its own pressed/item_selected
	# signal. Removing it from the tree synchronously in that callback makes
	# Godot try to mutate a locked signal emitter. Hide and disable it now so
	# Containers stop laying it out, then let queue_free retire it safely.
	if node is CanvasItem:
		(node as CanvasItem).hide()
	elif node is CanvasLayer:
		(node as CanvasLayer).hide()
	if node is Control:
		var control := node as Control
		control.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if control.has_focus():
			control.release_focus()
	# Release stable child names immediately so the replacement tree can reuse
	# paths such as `town-mainAction` before the old node reaches frame-end.
	# 必须递归整棵子树:退役树在帧末释放前仍在场景树里,孙子节点若保留
	# 原名,重建后的 find_child 会按树序先命中垂死实例(焦点恢复等逻辑
	# 会抓住它,随后随树释放而静默失效)。
	_release_names_recursive(node)
	node.set_process(false)
	node.set_process_input(false)
	node.set_process_unhandled_input(false)
	node.queue_free()
	return true


static func _release_names_recursive(node: Node) -> void:
	node.name = "_Retiring%d" % node.get_instance_id()
	for child: Node in node.get_children():
		_release_names_recursive(child)


static func retire_children(parent: Node) -> int:
	if parent == null or not is_instance_valid(parent):
		return 0
	var retired := 0
	for child: Node in parent.get_children():
		if retire(child):
			retired += 1
	return retired
