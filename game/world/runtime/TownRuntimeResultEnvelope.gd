extends RefCounted


# 社会事务/动作选项域的结果信封工厂(六文件孪生收敛,snake_case 键为该域
# 既有协议,与存档链 errorCode 信封是不同协议不混用)。

static func success(value: Variant) -> Dictionary:
	return {
		"ok": true,
		"error_code": "",
		"reason": "",
		"value": value,
	}


static func failure(error_code: String, reason: String) -> Dictionary:
	return {
		"ok": false,
		"error_code": error_code,
		"reason": reason,
	}
