extends SceneTree


const MANIFEST_PATH := (
	"res://assets/ui/startup/candidates/"
	+ "startup_image_asset_geometry_manifest_v2.json"
)
const STARTUP_SCREEN_PATH := "res://ui/startup/StartupScreen.gd"


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var failures: Array[String] = []
	var manifest := _load_json(MANIFEST_PATH)
	if manifest.is_empty():
		failures.append("精确尺寸资产清单不可读。")
		_finish(failures, 0)
		return
	var check_count := 0
	var reference := manifest.get("reference", {}) as Dictionary
	var maximum_axis_difference := float(
		reference.get("maximumAxisScaleDifferenceRatio", 0.0)
	)
	for plaque_value: Variant in manifest.get("plaques", []):
		var plaque := plaque_value as Dictionary
		check_count += _check_asset(
			String(plaque.get("id", "plaque")),
			String(plaque.get("path", "")),
			_array_size(plaque.get("designSize", [])),
			_array_size(plaque.get("sourceCrop", []), 2),
			float(plaque.get("minimumAlphaCoverage", 1.0)),
			maximum_axis_difference,
			failures,
		)
	var states := manifest.get("states", []) as Array
	for family_value: Variant in manifest.get("buttonFamilies", []):
		var family := family_value as Dictionary
		var family_id := String(family.get("id", "button"))
		var design_size := _array_size(family.get("designSize", []))
		var source_size := _array_size(family.get("sourceCrop", []), 2)
		var path_pattern := String(family.get("pathPattern", ""))
		for state_value: Variant in states:
			var state := String(state_value)
			check_count += _check_asset(
				"%s.%s" % [family_id, state],
				path_pattern % state,
				design_size,
				source_size,
				float(family.get("minimumAlphaCoverage", 1.0)),
				maximum_axis_difference,
				failures,
			)
	check_count += _check_runtime_source(failures)
	_finish(failures, check_count)


func _check_asset(
	asset_id: String,
	path: String,
	expected_size: Vector2i,
	source_size: Vector2i,
	minimum_alpha_coverage: float,
	maximum_axis_difference: float,
	failures: Array[String],
) -> int:
	var checks := 0
	var image := Image.new()
	var load_error := image.load(ProjectSettings.globalize_path(path))
	checks += 1
	if load_error != OK or image.is_empty():
		failures.append("%s 资产缺失：%s" % [asset_id, path])
		return checks
	checks += 1
	if image.get_size() != expected_size:
		failures.append(
			"%s 画布尺寸错误：expected=%s actual=%s"
			% [asset_id, expected_size, image.get_size()]
		)
	checks += 1
	var used_rect := image.get_used_rect()
	var coverage := (
		float(used_rect.size.x * used_rect.size.y)
		/ float(maxi(expected_size.x * expected_size.y, 1))
	)
	if coverage < minimum_alpha_coverage:
		failures.append(
			"%s alpha 边界过短：coverage=%.4f minimum=%.4f"
			% [asset_id, coverage, minimum_alpha_coverage]
		)
	checks += 1
	if source_size.x <= 0 or source_size.y <= 0:
		failures.append("%s 缺少有效来源裁切尺寸。" % asset_id)
	else:
		var scale_x := float(expected_size.x) / float(source_size.x)
		var scale_y := float(expected_size.y) / float(source_size.y)
		var difference := absf(scale_x - scale_y) / maxf(scale_x, scale_y)
		if difference > maximum_axis_difference:
			failures.append(
				"%s 横纵倍率不一致：x=%.6f y=%.6f difference=%.6f"
				% [asset_id, scale_x, scale_y, difference]
			)
	return checks


func _check_runtime_source(failures: Array[String]) -> int:
	var file := FileAccess.open(STARTUP_SCREEN_PATH, FileAccess.READ)
	if file == null:
		failures.append("StartupScreen 源码不可读。")
		return 1
	var source := file.get_as_text()
	file.close()
	var checks := 5
	if source.contains("开发版"):
		failures.append("StartupScreen 不得显示内部‘开发版’兜底文案。")
	if source.contains("StartupVersionPlaque"):
		failures.append("StartupScreen 不得创建无正式版本号的版本底牌。")
	if source.contains("_add_nine_patch_layer"):
		failures.append("启动按钮、摘要条和状态条不得通过 NinePatch 变形。")
	if source.contains("StartupStatusPlaque"):
		failures.append("StartupScreen 不得创建常驻 Provider 成功状态底牌。")
	if source.contains("连接正常"):
		failures.append("StartupScreen 不得常驻显示无操作价值的连接成功文案。")
	return checks


func _array_size(value: Variant, offset: int = 0) -> Vector2i:
	if not value is Array:
		return Vector2i.ZERO
	var numbers := value as Array
	if numbers.size() < offset + 2:
		return Vector2i.ZERO
	return Vector2i(int(numbers[offset]), int(numbers[offset + 1]))


func _load_json(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	return parsed as Dictionary if parsed is Dictionary else {}


func _finish(failures: Array[String], checks: int) -> void:
	if failures.is_empty():
		print("STARTUP_IMAGE_ASSET_GEOMETRY_PASS checks=%d" % checks)
		quit(0)
		return
	for failure: String in failures:
		push_error(failure)
	push_error(
		"STARTUP_IMAGE_ASSET_GEOMETRY_FAILED checks=%d failures=%d"
		% [checks, failures.size()]
	)
	quit(1)
