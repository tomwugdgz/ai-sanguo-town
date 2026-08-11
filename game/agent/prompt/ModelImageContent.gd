class_name AgentModelImageContent
extends RefCounted


# 照片 ref 为内容寻址（字节 SHA-256），data URL 按 ref+mime 缓存不会失效；
# base64 使字节膨胀 33%，重复编译请求不再重复编码。
const MAX_DATA_URL_CACHE_ENTRIES := 24
static var _data_url_cache: Dictionary = {}


static func build(
	text: String,
	source: Variant,
	photo_content_resolver: Object,
) -> Dictionary:
	var collection := _collect_photos(source)
	if not bool(collection.get("ok", false)):
		return collection
	var photos := collection["photos"] as Array
	if photos.is_empty():
		return {"ok": true, "content": text}
	if (
		photo_content_resolver == null
		or not photo_content_resolver.has_method("resolve_photo")
	):
		return {"ok": false, "errors": ["模型输入包含照片，但没有可用的照片内容解析器"]}
	var parts: Array[Dictionary] = [{"type": "text", "text": text}]
	for photo_value: Variant in photos:
		var photo := photo_value as Dictionary
		var ref := String(photo["ref"])
		var mime_type := String(photo["mime_type"])
		if not _safe_image_mime_type(mime_type):
			return {"ok": false, "errors": ["照片媒体类型不受支持：%s" % mime_type]}
		var cache_key := "%s|%s" % [ref, mime_type]
		if _data_url_cache.has(cache_key):
			parts.append({
				"type": "image_url",
				"image_url": {"url": _data_url_cache[cache_key]},
			})
			continue
		var resolved: Variant = photo_content_resolver.call(
			"resolve_photo",
			ref,
			mime_type,
		)
		if typeof(resolved) != TYPE_DICTIONARY:
			return {"ok": false, "errors": ["照片内容解析器返回了非法结果：%s" % ref]}
		var result := resolved as Dictionary
		if not bool(result.get("ok", false)):
			return {
				"ok": false,
				"errors": result.get("errors", ["无法取得照片内容：%s" % ref]),
			}
		var bytes_value: Variant = result.get("bytes")
		if (
			typeof(bytes_value) != TYPE_PACKED_BYTE_ARRAY
			or (bytes_value as PackedByteArray).is_empty()
		):
			return {"ok": false, "errors": ["照片内容为空或类型非法：%s" % ref]}
		var data_url := "data:%s;base64,%s" % [
			mime_type,
			Marshalls.raw_to_base64(bytes_value as PackedByteArray),
		]
		if _data_url_cache.size() >= MAX_DATA_URL_CACHE_ENTRIES:
			_data_url_cache.clear()
		_data_url_cache[cache_key] = data_url
		parts.append({
			"type": "image_url",
			"image_url": {"url": data_url},
		})
	return {"ok": true, "content": parts}


static func _collect_photos(source: Variant) -> Dictionary:
	var photos: Array[Dictionary] = []
	var mime_by_ref := {}
	var error := _collect(source, photos, mime_by_ref)
	if not error.is_empty():
		return {"ok": false, "errors": [error]}
	return {"ok": true, "photos": photos}


static func _collect(
	value: Variant,
	photos: Array[Dictionary],
	mime_by_ref: Dictionary,
) -> String:
	if typeof(value) == TYPE_ARRAY:
		for item: Variant in value as Array:
			var error := _collect(item, photos, mime_by_ref)
			if not error.is_empty():
				return error
		return ""
	if typeof(value) != TYPE_DICTIONARY:
		return ""
	var data := value as Dictionary
	if data.has("ref") and data.has("mime_type"):
		var ref := String(data.get("ref", ""))
		var mime_type := String(data.get("mime_type", ""))
		if not ref.is_empty() and not mime_type.is_empty():
			if mime_by_ref.has(ref):
				if String(mime_by_ref[ref]) != mime_type:
					return "同一照片引用对应了不同媒体类型：%s" % ref
			else:
				mime_by_ref[ref] = mime_type
				photos.append({"ref": ref, "mime_type": mime_type})
	for item: Variant in data.values():
		var error := _collect(item, photos, mime_by_ref)
		if not error.is_empty():
			return error
	return ""


static func _safe_image_mime_type(mime_type: String) -> bool:
	if not mime_type.to_lower().begins_with("image/") or mime_type.length() <= 6:
		return false
	for character in mime_type.substr(6):
		var code := character.unicode_at(0)
		var is_lower_letter := code >= 97 and code <= 122
		var is_upper_letter := code >= 65 and code <= 90
		var is_digit := code >= 48 and code <= 57
		if (
			not is_lower_letter
			and not is_upper_letter
			and not is_digit
			and character not in [".", "+", "-"]
		):
			return false
	return true
