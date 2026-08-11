extends RefCounted


# 世界数据侧标量工具(孪生收敛):几何三件+CJK 判定。

static func polygon_area(points: PackedVector2Array) -> float:
	if points.size() < 3:
		return 0.0
	var doubled_area := 0.0
	for index in range(points.size()):
		var current := points[index]
		var next := points[(index + 1) % points.size()]
		doubled_area += current.x * next.y - next.x * current.y
	return absf(doubled_area) * 0.5

static func contains_cjk(text: String) -> bool:
	for index in text.length():
		var code := text.unicode_at(index)
		if code >= 0x3400 and code <= 0x9FFF:
			return true
	return false


static func exact_keys(value: Dictionary, expected: Array) -> bool:
	var actual: Array[String] = []
	for key_value: Variant in value:
		actual.append(String(key_value))
	actual.sort()
	var normalized_expected: Array[String] = []
	for key_value: Variant in expected:
		normalized_expected.append(String(key_value))
	normalized_expected.sort()
	return actual == normalized_expected


static func validate_capabilities(
	place_name: String,
	capabilities: Dictionary,
	errors: PackedStringArray,
) -> void:
	for key_value in capabilities:
		if not key_value is String or (key_value as String).strip_edges().is_empty():
			errors.append("地点 %s 的 capability 名称必须为非空字符串" % place_name)
			continue
		if not capabilities[key_value] is bool:
			errors.append(
				"地点 %s 的 capability %s 必须为布尔值"
				% [place_name, key_value],
			)


static func is_number(value: Variant) -> bool:
	return (
		typeof(value) in [TYPE_INT, TYPE_FLOAT]
		and is_finite(float(value))
	)


static func is_ascii_digit(character: String) -> bool:
	if character.length() != 1:
		return false
	var code := character.unicode_at(0)
	return code >= 48 and code <= 57


static func is_valid_clock(clock: String) -> bool:
	if clock.length() != 5 or clock.substr(2, 1) != ":":
		return false
	for index in [0, 1, 3, 4]:
		if clock.substr(index, 1) not in "0123456789":
			return false
	var hour := int(clock.substr(0, 2))
	var minute := int(clock.substr(3, 2))
	return hour >= 0 and hour <= 23 and minute >= 0 and minute <= 59


static func is_integer_number(value: Variant) -> bool:
	return (
		typeof(value) == TYPE_INT
		or (
			typeof(value) == TYPE_FLOAT
			and is_finite(float(value))
			and float(value) == roundf(float(value))
		)
	)


static func exact_keys_sorted(
	value: Dictionary,
	expected: Array,
) -> bool:
	var actual := value.keys()
	var wanted := expected.duplicate()
	actual.sort()
	wanted.sort()
	return actual == wanted


static func sorted_dictionaries(values: Array, key: String) -> Array:
	var result := values.duplicate(true)
	result.sort_custom(func(left: Variant, right: Variant) -> bool:
		var left_dictionary := left as Dictionary
		var right_dictionary := right as Dictionary
		return str(left_dictionary.get(key, "")) < str(right_dictionary.get(key, ""))
	)
	return result


static func resident_id_is_safe(resident_id: String) -> bool:
	if resident_id.is_empty() or resident_id.length() > 128:
		return false
	for character in resident_id:
		var code := character.unicode_at(0)
		var is_ascii_letter := code >= 97 and code <= 122
		var is_digit := code >= 48 and code <= 57
		if not is_ascii_letter and not is_digit and character not in ["_", "-"]:
			return false
	return true
