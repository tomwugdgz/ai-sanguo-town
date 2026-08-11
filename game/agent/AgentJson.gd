class_name AgentJson
extends RefCounted


static func normalize_numbers(value: Variant) -> Variant:
	match typeof(value):
		TYPE_DICTIONARY:
			var normalized := {}
			for key: Variant in value:
				normalized[key] = normalize_numbers(value[key])
			return normalized
		TYPE_ARRAY:
			var normalized: Array = []
			for item: Variant in value:
				normalized.append(normalize_numbers(item))
			return normalized
		TYPE_FLOAT:
			var number := float(value)
			return int(number) if is_finite(number) and number == floor(number) else number
		_:
			return value


static func content_sha256(value: Variant) -> String:
	return JSON.stringify(normalize_numbers(value), "", true).sha256_text()
