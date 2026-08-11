class_name ProviderTestDoubles
extends RefCounted


class ResultCollector:
	var values: Array[Dictionary] = []

	func collect(value: Dictionary) -> void:
		values.append(value.duplicate(true))


class ImmediateTransport:
	extends RefCounted

	var requests: Array[Dictionary] = []
	var response: Dictionary = {}
	var queued_responses: Array[Dictionary] = []

	func queue_response(value: Dictionary) -> void:
		queued_responses.append(value.duplicate(true))

	func request_json(
		url: String,
		headers: PackedStringArray,
		body: Dictionary,
		on_complete: Callable,
	) -> int:
		requests.append({
			"url": url,
			"headers": headers.duplicate(),
			"body": body.duplicate(true),
		})
		var next_response := response
		if not queued_responses.is_empty():
			next_response = queued_responses.pop_front()
		if next_response.is_empty():
			return ERR_UNAVAILABLE
		on_complete.call(next_response.duplicate(true))
		return OK


class ManualTransport:
	extends RefCounted

	var requests: Array[Dictionary] = []
	var callbacks: Array[Callable] = []

	func request_json(
		url: String,
		headers: PackedStringArray,
		body: Dictionary,
		on_complete: Callable,
	) -> int:
		requests.append({
			"url": url,
			"headers": headers.duplicate(),
			"body": body.duplicate(true),
		})
		callbacks.append(on_complete)
		return OK

	func complete(index: int, response: Dictionary) -> void:
		# 回调捕获 provider、provider 又持有本 transport，调用后必须释放
		# 存储的 Callable 断开引用环，否则退出时报资源泄漏。
		var callback := callbacks[index]
		callbacks[index] = Callable()
		callback.call(response.duplicate(true))
