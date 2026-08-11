class_name AgentSessionEpoch
extends RefCounted


var _epoch := 1
var _active := true


func capture() -> int:
	return _epoch


func is_current(captured_epoch: int) -> bool:
	return _active and captured_epoch == _epoch


func invalidate() -> void:
	_active = false
	_epoch += 1
