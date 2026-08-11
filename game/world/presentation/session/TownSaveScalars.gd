class_name TownSaveScalars
extends RefCounted
## 存档链路标量工具库(批次E之2):三组孪生函数收敛的唯一实现。
## 合并前证据:_days_in_month 四版穷举对拍零差异;_ascii_digits 四版仅变量名差;
## _is_saved_at 三版逐检查项同构(Manifest 的 Variant 守卫拆为 is_saved_at_value)。


static func ascii_digits(value: String) -> bool:
	if value.is_empty():
		return false
	for character: String in value:
		var code := character.unicode_at(0)
		if code < 48 or code > 57:
			return false
	return true


static func days_in_month(month: int, year: int) -> int:
	if month == 2:
		var leap_year := (
			year % 400 == 0
			or (year % 4 == 0 and year % 100 != 0)
		)
		return 29 if leap_year else 28
	if month in [4, 6, 9, 11]:
		return 30
	return 31


static func is_saved_at(text: String) -> bool:
	if text != text.strip_edges() or not [19, 20, 25].has(text.length()):
		return false
	if (
		text[4] != "-"
		or text[7] != "-"
		or text[10] != "T"
		or text[13] != ":"
		or text[16] != ":"
	):
		return false
	var date_time_digits := (
		text.substr(0, 4)
		+ text.substr(5, 2)
		+ text.substr(8, 2)
		+ text.substr(11, 2)
		+ text.substr(14, 2)
		+ text.substr(17, 2)
	)
	if not ascii_digits(date_time_digits):
		return false
	var year := int(text.substr(0, 4))
	var month := int(text.substr(5, 2))
	var day := int(text.substr(8, 2))
	var hour := int(text.substr(11, 2))
	var minute := int(text.substr(14, 2))
	var second := int(text.substr(17, 2))
	if (
		year < 1
		or month < 1
		or month > 12
		or day < 1
		or day > days_in_month(month, year)
		or hour > 23
		or minute > 59
		or second > 59
	):
		return false
	if text.length() == 19:
		return true
	if text.length() == 20:
		return text[19] == "Z"
	if (
		not ["+", "-"].has(text[19])
		or text[22] != ":"
		or not ascii_digits(text.substr(20, 2) + text.substr(23, 2))
	):
		return false
	return int(text.substr(20, 2)) <= 23 and int(text.substr(23, 2)) <= 59


static func is_saved_at_value(value: Variant) -> bool:
	if not value is String:
		return false
	return is_saved_at(value as String)


static func sequence_from_id(id: String, prefix: String) -> int:
	if not id.begins_with(prefix):
		return -1
	var suffix := id.trim_prefix(prefix)
	if not suffix.is_valid_int() or suffix.begins_with("+"):
		return -1
	var sequence := int(suffix)
	if sequence <= 0 or id != "%s%d" % [prefix, sequence]:
		return -1
	return sequence
