extends SceneTree


const STARTUP_THEME := preload("res://ui/startup/StartupButtonImageTheme.gd")
const COMMERCIAL_GATE := preload(
	"res://ui/common/tools/CommonUiCommercialGate.gd"
)
const MAIN_MENU_FONT_PATH := (
	"res://assets/ui/startup/fonts/noto_sans_cjk_sc_medium/"
	+ "NotoSansCJKsc-Medium.otf"
)
const MAIN_MENU_FONT_IMPORT_PATH := (
	MAIN_MENU_FONT_PATH + ".import"
)
const COVERAGE_SAMPLE := (
	"花子的AI小镇镇上的日子还在继续"
	+ "继续游戏开始新游戏加载游戏模型设置游戏设置退出游戏"
	+ "第天居民存档损坏恢复保存未完成"
)


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var failures: Array[String] = []
	var checks := 0
	var theme := STARTUP_THEME.create() as Theme
	checks += _expect(theme != null, "启动 Theme 必须可创建。", failures)
	if theme == null:
		_finish(failures, checks)
		return
	checks += _validate_import_contract(failures)
	checks += _validate_typography_roles(theme, failures)
	checks += _validate_control_fit(theme, failures)
	checks += _validate_button_contrast(failures)
	checks += _validate_coverage(theme, failures)
	_finish(failures, checks)


func _validate_import_contract(failures: Array[String]) -> int:
	var checks := 0
	var required_lines: Array[String] = [
		"antialiasing=1",
		"allow_system_fallback=false",
		"hinting=1",
		"subpixel_positioning=0",
		"keep_rounding_remainders=false",
		"oversampling=1.0",
		"fallbacks=[]",
	]
	for import_path: String in [MAIN_MENU_FONT_IMPORT_PATH]:
		var file := FileAccess.open(import_path, FileAccess.READ)
		checks += _expect(
			file != null,
			"主菜单黑体 import 合同不可读：%s" % import_path,
			failures,
		)
		if file == null:
			continue
		var source := file.get_as_text()
		file.close()
		for line: String in required_lines:
			checks += _expect(
				source.contains(line),
				"主菜单黑体 import 参数漂移：%s %s" % [import_path, line],
				failures,
			)
	return checks


func _validate_typography_roles(
	theme: Theme,
	failures: Array[String],
) -> int:
	var checks := 0
	var roles := {
		"StartupPrimaryButton": {
			"size": 32,
			"embolden": 0.0,
			"spacing": 2,
			"outline": 0,
			"shadow": Vector2i.ZERO,
			"color": Color("fff8e6"),
		},
		"StartupSecondaryButton": {
			"size": 32,
			"embolden": 0.0,
			"spacing": 2,
			"outline": 0,
			"shadow": Vector2i.ZERO,
			"color": Color("3f2818"),
		},
		"StartupQuietButton": {
			"size": 32,
			"embolden": 0.0,
			"spacing": 2,
			"outline": 0,
			"shadow": Vector2i.ZERO,
			"color": Color("fff8e6"),
		},
		"StartupSaveSummary": {
			"size": 32,
			"embolden": 0.0,
			"spacing": 2,
			"outline": 0,
			"shadow": Vector2i.ZERO,
			"color": Color("3f2818"),
		},
	}
	for role_name: String in roles:
		var role := roles[role_name] as Dictionary
		var variation_name := StringName(role_name)
		var font := theme.get_font(&"font", variation_name) as FontVariation
		checks += _expect(font != null, "%s 字体缺失。" % role_name, failures)
		checks += _expect(
			theme.get_font_size(&"font_size", variation_name) == int(role["size"]),
			"%s 字号必须保持 %dpx。" % [role_name, int(role["size"])],
			failures,
		)
		checks += _expect(
			theme.get_constant(&"outline_size", variation_name)
			== int(role["outline"]),
			"%s 描边必须保持 %dpx。" % [role_name, int(role["outline"])],
			failures,
		)
		checks += _expect(
			theme.get_color(&"font_color", variation_name)
			== (role["color"] as Color),
			"%s 文字颜色必须保持 %s。" % [role_name, role["color"]],
			failures,
		)
		if role_name.ends_with("Button"):
			var expected_shadow := role["shadow"] as Vector2i
			var actual_shadow := Vector2i(
				theme.get_constant(&"shadow_offset_x", variation_name),
				theme.get_constant(&"shadow_offset_y", variation_name),
			)
			checks += _expect(
				actual_shadow == expected_shadow,
				"%s 单向硬阴影偏移必须保持 %s。"
				% [role_name, expected_shadow],
				failures,
			)
		if font == null:
			continue
		checks += _expect(
			font.base_font != null
			and font.base_font.resource_path == MAIN_MENU_FONT_PATH,
			"%s 必须使用已确认的 Noto Sans CJK SC Medium。" % role_name,
			failures,
		)
		checks += _expect(
			font.spacing_glyph == int(role["spacing"]),
			"%s 字距必须保持 %dpx。"
			% [role_name, int(role["spacing"])],
			failures,
		)
		checks += _expect(
			is_equal_approx(font.variation_embolden, float(role["embolden"])),
			"%s 字重参数必须保持 %.3f。"
			% [role_name, float(role["embolden"])],
			failures,
		)
	return checks


func _validate_control_fit(theme: Theme, failures: Array[String]) -> int:
	var checks := 0
	var cases := [
		{
			"id": "primary",
			"variation": &"StartupPrimaryButton",
			"control_size": Vector2(459.0, 70.0),
			"texts": ["继续游戏", "开始新游戏", "加载游戏"],
		},
		{
			"id": "secondary",
			"variation": &"StartupSecondaryButton",
			"control_size": Vector2(222.0, 69.0),
			"texts": ["模型设置", "游戏设置"],
		},
		{
			"id": "quiet",
			"variation": &"StartupQuietButton",
			"control_size": Vector2(456.0, 65.0),
			"texts": ["退出游戏"],
		},
	]
	for case_value: Variant in cases:
		var test_case := case_value as Dictionary
		var variation := test_case["variation"] as StringName
		var control_size := test_case["control_size"] as Vector2
		var font := theme.get_font(&"font", variation)
		var font_size := theme.get_font_size(&"font_size", variation)
		var outline := theme.get_constant(&"outline_size", variation)
		var style := theme.get_stylebox(&"normal", variation)
		var safe_width := (
			control_size.x
			- style.get_content_margin(SIDE_LEFT)
			- style.get_content_margin(SIDE_RIGHT)
		)
		var safe_height := (
			control_size.y
			- style.get_content_margin(SIDE_TOP)
			- style.get_content_margin(SIDE_BOTTOM)
		)
		checks += _expect(
			font.get_height(font_size) + float(outline * 2) <= safe_height,
			"%s 文字高度超出控件内容区。" % String(test_case["id"]),
			failures,
		)
		for text_value: Variant in test_case["texts"]:
			var label := String(text_value)
			var pressure_width := ceilf(
				font.get_string_size(
					label,
					HORIZONTAL_ALIGNMENT_LEFT,
					-1,
					font_size,
				).x * 1.3
			)
			checks += _expect(
				pressure_width <= safe_width,
				"%s 130%% 文案超出控件内容区：%s width=%.0f safe=%.0f"
				% [String(test_case["id"]), label, pressure_width, safe_width],
				failures,
			)
	return checks


func _validate_coverage(theme: Theme, failures: Array[String]) -> int:
	var missing := ""
	for variation: StringName in [
		&"StartupPrimaryButton",
		&"StartupSaveSummary",
	]:
		var font := theme.get_font(&"font", variation)
		for character: String in COVERAGE_SAMPLE:
			if not font.has_char(character.unicode_at(0)):
				missing += "%s:%s " % [variation, character]
	return _expect(
		missing.is_empty(),
		"启动玩家可见文字存在缺字：%s" % missing,
		failures,
	)


func _validate_button_contrast(failures: Array[String]) -> int:
	var checks := 0
	var cases := [
		{
			"id": "primary",
			"path": (
				"res://assets/ui/startup/runtime/"
				+ "button_states/primary_normal.png"
			),
			"foreground": Color("fff8e6"),
		},
		{
			"id": "quiet",
			"path": (
				"res://assets/ui/startup/runtime/"
				+ "button_states/quiet_normal.png"
			),
			"foreground": Color("fff8e6"),
		},
	]
	for case_value: Variant in cases:
		var test_case := case_value as Dictionary
		var image := Image.new()
		var path := String(test_case["path"])
		var load_error := image.load(ProjectSettings.globalize_path(path))
		checks += _expect(
			load_error == OK and not image.is_empty(),
			"%s 按钮对比度样本不可读。" % String(test_case["id"]),
			failures,
		)
		if load_error != OK or image.is_empty():
			continue
		var background := image.get_pixel(
			image.get_width() / 2,
			image.get_height() / 2,
		)
		var ratio := COMMERCIAL_GATE.contrast_ratio(
			test_case["foreground"] as Color,
			background,
		)
		checks += _expect(
			ratio >= 3.0,
			"%s 大字对比度不足：ratio=%.3f minimum=3.000"
			% [String(test_case["id"]), ratio],
			failures,
		)
	return checks


func _expect(
	condition: bool,
	message: String,
	failures: Array[String],
) -> int:
	if not condition:
		failures.append(message)
	return 1


func _finish(failures: Array[String], checks: int) -> void:
	if failures.is_empty():
		print(
			(
				"STARTUP_TYPOGRAPHY_CONTRACT_PASS checks=%d "
				+ "project_ui_references=4 text_pressure=130%% exact_geometry=true"
			)
			% checks
		)
		quit(0)
		return
	for failure: String in failures:
		push_error(failure)
	push_error(
		"STARTUP_TYPOGRAPHY_CONTRACT_FAILED checks=%d failures=%d"
		% [checks, failures.size()]
	)
	quit(1)
