class_name AgentTestFormat
extends RefCounted


const MAX_INLINE_CHARS := 2400
const MAX_DIFFS := 12
const REDACTED := "[REDACTED]"


static func failure(
	suite_path: String,
	message: String,
	assertion: String,
	expected: Variant,
	actual: Variant,
	stack: Array,
	context: Dictionary = {},
) -> String:
	var callsite := _callsite(stack)
	var lines: Array[String] = [
		"[FAIL] %s" % suite_path.trim_prefix("res://tests/agent/"),
		"case: %s" % String(callsite.get("function", "unknown")),
		"source: %s:%d" % [
			String(callsite.get("source", suite_path)).trim_prefix("res://"),
			int(callsite.get("line", 0)),
		],
		"assertion: %s" % assertion,
		"message: %s" % message,
	]
	if assertion != "expect_true":
		lines.append("expected: %s" % render(expected))
		lines.append("actual:   %s" % render(actual))
		var differences := differences(expected, actual)
		if not differences.is_empty():
			lines.append("diff:")
			for difference: String in differences:
				lines.append("  %s" % difference)
	if not context.is_empty():
		lines.append("context: %s" % render(context))
	return "\n".join(lines)


static func render(value: Variant) -> String:
	var safe_value: Variant = sanitize(value)
	var rendered: String = JSON.stringify(safe_value, "  ", true)
	if rendered.is_empty() and safe_value != null:
		rendered = str(safe_value)
	if rendered.length() <= MAX_INLINE_CHARS:
		return rendered
	return "%s… <%d chars>" % [rendered.left(MAX_INLINE_CHARS), rendered.length()]


static func sanitize(value: Variant, depth: int = 0) -> Variant:
	if depth > 16:
		return "<max-depth>"
	match typeof(value):
		TYPE_DICTIONARY:
			var result: Dictionary = {}
			for key: Variant in value as Dictionary:
				var key_text := String(key)
				if _is_sensitive_key(key_text):
					result[key] = REDACTED
				else:
					result[key] = sanitize((value as Dictionary)[key], depth + 1)
			return result
		TYPE_ARRAY:
			var result: Array = []
			for item: Variant in value as Array:
				result.append(sanitize(item, depth + 1))
			return result
		TYPE_PACKED_STRING_ARRAY:
			return Array(value as PackedStringArray)
		TYPE_PACKED_BYTE_ARRAY:
			return "<%d bytes>" % (value as PackedByteArray).size()
		TYPE_STRING:
			var text := String(value)
			if text.to_lower().begins_with("bearer "):
				return "Bearer %s" % REDACTED
			return text
	return value


static func differences(expected: Variant, actual: Variant) -> Array[String]:
	var result: Array[String] = []
	_collect_differences(expected, actual, "$", result)
	return result


static func subset_differences(expected: Variant, actual: Variant) -> Array[String]:
	var result: Array[String] = []
	_collect_subset_differences(expected, actual, "$", result)
	return result


static func _collect_subset_differences(
	expected: Variant,
	actual: Variant,
	path: String,
	result: Array[String],
) -> void:
	if result.size() >= MAX_DIFFS:
		return
	if typeof(expected) != TYPE_DICTIONARY:
		if expected != actual:
			result.append("%s expected %s, actual %s" % [path, render(expected), render(actual)])
		return
	if typeof(actual) != TYPE_DICTIONARY:
		result.append("%s expected object, actual %s" % [path, render(actual)])
		return
	var expected_data := expected as Dictionary
	var actual_data := actual as Dictionary
	for key: Variant in expected_data:
		var child_path := "%s.%s" % [path, key]
		if not actual_data.has(key):
			result.append("%s missing; expected %s" % [child_path, render(expected_data[key])])
		elif result.size() < MAX_DIFFS:
			_collect_subset_differences(
				expected_data[key],
				actual_data[key],
				child_path,
				result,
			)
		if result.size() >= MAX_DIFFS:
			return


static func _collect_differences(
	expected: Variant,
	actual: Variant,
	path: String,
	result: Array[String],
) -> void:
	if result.size() >= MAX_DIFFS:
		return
	if typeof(expected) != typeof(actual):
		result.append(
			"%s type expected %s, actual %s" % [
				path,
				type_string(typeof(expected)),
				type_string(typeof(actual)),
			]
		)
		return
	match typeof(expected):
		TYPE_DICTIONARY:
			var expected_data: Dictionary = expected as Dictionary
			var actual_data: Dictionary = actual as Dictionary
			for key: Variant in expected_data:
				var child_path := "%s.%s" % [path, key]
				if not actual_data.has(key):
					result.append("%s missing; expected %s" % [child_path, render(expected_data[key])])
					if result.size() >= MAX_DIFFS:
						return
					continue
				_collect_differences(expected_data[key], actual_data[key], child_path, result)
				if result.size() >= MAX_DIFFS:
					return
			for key: Variant in actual_data:
				if not expected_data.has(key):
					result.append("%s.%s unexpected; actual %s" % [path, key, render(actual_data[key])])
					if result.size() >= MAX_DIFFS:
						return
		TYPE_ARRAY:
			var expected_items: Array = expected as Array
			var actual_items: Array = actual as Array
			if expected_items.size() != actual_items.size():
				result.append(
					"%s.length expected %d, actual %d" % [
						path,
						expected_items.size(),
						actual_items.size(),
					]
				)
			var shared_size: int = mini(expected_items.size(), actual_items.size())
			for index in shared_size:
				_collect_differences(
					expected_items[index],
					actual_items[index],
					"%s[%d]" % [path, index],
					result,
				)
				if result.size() >= MAX_DIFFS:
					return
		_:
			if expected != actual:
				result.append("%s expected %s, actual %s" % [path, render(expected), render(actual)])


static func _callsite(stack: Array) -> Dictionary:
	var fallback: Dictionary = {}
	for frame_value: Variant in stack:
		if typeof(frame_value) != TYPE_DICTIONARY:
			continue
		var frame := frame_value as Dictionary
		var source := String(frame.get("source", ""))
		var function_name := String(frame.get("function", ""))
		if fallback.is_empty() and not source.ends_with("AgentTestCase.gd"):
			fallback = frame
		if (
			not source.ends_with("AgentTestCase.gd")
			and (function_name.begins_with("_test_") or function_name.begins_with("test_"))
		):
			return frame
	return fallback


static func _is_sensitive_key(key: String) -> bool:
	var normalized := key.to_lower().replace("-", "_")
	return (
		"api_key" in normalized
		or "authorization" in normalized
		or normalized.ends_with("token")
		or normalized.ends_with("secret")
		or normalized == "key"
	)
