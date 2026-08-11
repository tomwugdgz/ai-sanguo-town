extends RefCounted


# 世界侧标准结果信封工厂(E6 起点:三键 {ok,errorCode,retryable} 协议的
# 六份逐字孪生收敛;带 errors 数组的七行变体族与 snake_case 域协议另行)。

static func failure(error_code: String) -> Dictionary:
	return {
		"ok": false,
		"errorCode": error_code,
		"retryable": false,
	}


static func failure_with(
	error_code: String,
	retryable: bool,
	errors: Array = [],
) -> Dictionary:
	return {
		"ok": false,
		"errorCode": error_code,
		"retryable": retryable,
		"errors": errors.duplicate(true),
	}


static func success_changed(changed: bool) -> Dictionary:
	return {
		"ok": true,
		"errorCode": "",
		"retryable": false,
		"changed": changed,
	}


static func failure_retryable(error_code: String, retryable: bool) -> Dictionary:
	return {
		"ok": false,
		"errorCode": error_code,
		"retryable": retryable,
	}


static func failure_minimal(error_code: String) -> Dictionary:
	return {
		"ok": false,
		"errorCode": error_code,
	}


static func success_with(extra: Dictionary = {}) -> Dictionary:
	var result := {
		"ok": true,
		"errorCode": "",
		"retryable": false,
	}
	result.merge(extra, true)
	return result
