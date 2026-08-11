extends RefCounted


# UI 屏幕适配器信号断连孪生收敛(18 份两变体,差异仅回调方法名,由调用侧传入)。

static func disconnect_view_model(adapter: Object, callback: Callable) -> void:
	if adapter == null or not adapter.has_signal("view_model_changed"):
		return
	if adapter.is_connected("view_model_changed", callback):
		adapter.disconnect("view_model_changed", callback)
