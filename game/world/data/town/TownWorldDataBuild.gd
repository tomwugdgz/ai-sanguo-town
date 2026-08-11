extends SceneTree

const SOURCE_DIR := "res://world/data/town/source"
const OUTPUT_PATH := "res://world/data/town/town_world.json"
const BUILDER := preload("res://world/data/town/TownWorldDataBuilder.gd")
const VALIDATOR := preload("res://world/data/town/TownWorldDataValidator.gd")
const MOVEMENT_VALIDATOR := preload("res://world/data/town/TownWorldMovementValidator.gd")
const PROP_VALIDATOR := preload("res://world/data/town/TownWorldPropValidator.gd")


func _initialize() -> void:
	var source_dir := _argument_value("--source-dir", SOURCE_DIR)
	var output_path := _argument_value("--output-path", OUTPUT_PATH)
	var errors := VALIDATOR.validate_source_directory(source_dir)
	if not errors.is_empty():
		_report_errors(errors)
		quit(1)
		return
	var activity_report := VALIDATOR.validate_activity_integration_source(
		source_dir
	) as Dictionary
	if not bool(activity_report.get("formalExecutable", false)):
		errors.append_array(
			activity_report.get(
				"errors",
				PackedStringArray(),
			) as PackedStringArray
		)
		errors.append("Activity Integration 未达到 formalExecutable")
		_report_errors(errors)
		quit(1)
		return
	var data := BUILDER.build_from_source(source_dir)
	if data.is_empty():
		printerr("TOWN_WORLD_DATA_BUILD_FAIL: 源数据结构无法构建")
		quit(1)
		return
	errors.append_array(VALIDATOR.validate_foundation(data))
	errors.append_array(VALIDATOR.validate_outdoor_perception(data))
	errors.append_array(VALIDATOR.validate_indoor_perception(data))
	errors.append_array(
		VALIDATOR.validate_activity_integration_receipt(
			data,
			source_dir,
		)
	)
	errors.append_array(MOVEMENT_VALIDATOR.validate(data))
	errors.append_array(PROP_VALIDATOR.validate(data))
	if not errors.is_empty():
		_report_errors(errors)
		quit(1)
		return
	if not BUILDER.write_catalog(output_path, data):
		printerr("TOWN_WORLD_DATA_BUILD_FAIL: 无法写入 %s" % output_path)
		quit(1)
		return
	print("TOWN_WORLD_DATA_BUILD_PASS")
	quit(0)


func _report_errors(errors: PackedStringArray) -> void:
	for error in errors:
		printerr("TOWN_WORLD_DATA_BUILD_FAIL: %s" % error)


func _argument_value(flag: String, fallback: String) -> String:
	var arguments := OS.get_cmdline_user_args()
	var index := arguments.find(flag)
	if index < 0 or index + 1 >= arguments.size():
		return fallback
	var value := arguments[index + 1].strip_edges()
	return value if not value.is_empty() else fallback
