class_name TownAudioDisplaySettingsStore
extends RefCounted


const DEFAULT_SETTINGS_PATH := "user://player_settings.cfg"
const SCHEMA_VERSION := 1
const META_SECTION := "meta"
const AUDIO_SECTION := "audio"
const DISPLAY_SECTION := "display"
const AUDIO_KEYS := [
	"masterPercent",
	"musicPercent",
	"ambiencePercent",
	"sfxPercent",
	"uiPercent",
]
const AUDIO_STORAGE_KEYS := {
	"masterPercent": "master_percent",
	"musicPercent": "music_percent",
	"ambiencePercent": "ambience_percent",
	"sfxPercent": "sfx_percent",
	"uiPercent": "ui_percent",
}
const WINDOW_MODE_IDS := [
	"windowed",
	"borderless_fullscreen",
	"exclusive_fullscreen",
]
const UI_SCALE_PERCENTS := [100]
const SETTINGS_KEYS := ["audio", "display"]
const AUDIO_DATA_KEYS := [
	"masterPercent",
	"musicPercent",
	"ambiencePercent",
	"sfxPercent",
	"uiPercent",
	"muted",
]
const DISPLAY_DATA_KEYS := [
	"windowModeId",
	"windowedResolutionId",
	"uiScalePercent",
	"reducedFlashingEnabled",
]
const CONFIG_SECTIONS := [META_SECTION, AUDIO_SECTION, DISPLAY_SECTION]
const META_STORAGE_KEYS := ["schema_version"]
const AUDIO_STORAGE_FIELD_KEYS := [
	"master_percent",
	"music_percent",
	"ambience_percent",
	"sfx_percent",
	"ui_percent",
	"muted",
]
const DISPLAY_STORAGE_KEYS := [
	"window_mode_id",
	"windowed_resolution_id",
	"ui_scale_percent",
	"reduced_flashing_enabled",
]


var settings_path := DEFAULT_SETTINGS_PATH


func _init(path := DEFAULT_SETTINGS_PATH) -> void:
	settings_path = path


func load_settings(fallback_value: Variant) -> Dictionary:
	if typeof(fallback_value) != TYPE_DICTIONARY:
		return {
			"ok": false,
			"found": false,
			"settings": {},
			"errorCode": "SETTINGS_FALLBACK_INVALID",
			"message": "运行时设置基线无效，未读取本机设置。",
		}
	var fallback := fallback_value as Dictionary
	if not _raw_settings_are_valid(fallback):
		return {
			"ok": false,
			"found": false,
			"settings": {},
			"errorCode": "SETTINGS_FALLBACK_INVALID",
			"message": "运行时设置基线无效，未读取本机设置。",
		}
	var recovery := _recover_interrupted_replace(
		settings_path,
		"%s.bak" % settings_path,
		fallback,
	)
	if not bool(recovery.get("ok", false)):
		return {
			"ok": false,
			"found": true,
			"settings": sanitize_settings(fallback, fallback),
			"errorCode": "SETTINGS_RECOVERY_FAILED",
			"message": "上次设置写入中断，旧设置无法安全恢复。",
			"engineError": recovery.get("engineError", ERR_FILE_CORRUPT),
		}
	return _load_settings_file(settings_path, fallback)


func _load_settings_file(path: String, fallback: Dictionary) -> Dictionary:
	var config := ConfigFile.new()
	var load_error := config.load(path)
	if load_error == ERR_FILE_NOT_FOUND:
		return {
			"ok": true,
			"found": false,
			"settings": sanitize_settings(fallback, fallback),
			"errorCode": "",
			"message": "",
		}
	if load_error != OK:
		return {
			"ok": false,
			"found": true,
			"settings": sanitize_settings(fallback, fallback),
			"errorCode": "SETTINGS_LOAD_FAILED",
			"message": "本机设置无法读取，当前使用安全设置。",
		}
	var schema_value: Variant = config.get_value(
		META_SECTION,
		"schema_version",
		null,
	)
	if typeof(schema_value) != TYPE_INT or int(schema_value) != SCHEMA_VERSION:
		return {
			"ok": false,
			"found": true,
			"settings": sanitize_settings(fallback, fallback),
			"errorCode": "SETTINGS_SCHEMA_UNSUPPORTED",
			"message": "本机设置版本不受支持，当前使用安全设置。",
		}
	if not _config_shape_is_valid(config):
		return {
			"ok": false,
			"found": true,
			"settings": sanitize_settings(fallback, fallback),
			"errorCode": "SETTINGS_CORRUPT",
			"message": "本机设置内容损坏，当前使用安全设置。",
		}

	var raw := {
		"audio": {},
		"display": {},
	}
	var raw_audio := raw["audio"] as Dictionary
	var fallback_audio := fallback.get("audio", {}) as Dictionary
	for key: String in AUDIO_KEYS:
		raw_audio[key] = config.get_value(
			AUDIO_SECTION,
			String(AUDIO_STORAGE_KEYS[key]),
			fallback_audio.get(key, 0),
		)
	raw_audio["muted"] = config.get_value(
		AUDIO_SECTION,
		"muted",
		fallback_audio.get("muted", false),
	)
	var raw_display := raw["display"] as Dictionary
	var fallback_display := fallback.get("display", {}) as Dictionary
	raw_display["windowModeId"] = config.get_value(
		DISPLAY_SECTION,
		"window_mode_id",
		fallback_display.get("windowModeId", "windowed"),
	)
	raw_display["windowedResolutionId"] = config.get_value(
		DISPLAY_SECTION,
		"windowed_resolution_id",
		fallback_display.get("windowedResolutionId", "1920x1080"),
	)
	raw_display["uiScalePercent"] = config.get_value(
		DISPLAY_SECTION,
		"ui_scale_percent",
		fallback_display.get("uiScalePercent", 100),
	)
	raw_display["reducedFlashingEnabled"] = config.get_value(
		DISPLAY_SECTION,
		"reduced_flashing_enabled",
		fallback_display.get("reducedFlashingEnabled", false),
	)
	if not _raw_settings_are_valid(raw):
		return {
			"ok": false,
			"found": true,
			"settings": sanitize_settings(fallback, fallback),
			"errorCode": "SETTINGS_CORRUPT",
			"message": "本机设置内容损坏，当前使用安全设置。",
		}
	var sanitized := sanitize_settings(raw, fallback)
	return {
		"ok": true,
		"found": true,
		"settings": sanitized,
		"errorCode": "",
		"message": "",
		"schemaVersion": int(config.get_value(META_SECTION, "schema_version", 0)),
	}


func save_settings(settings_value: Variant) -> Dictionary:
	if typeof(settings_value) != TYPE_DICTIONARY:
		return {
			"ok": false,
			"errorCode": "SETTINGS_INVALID",
			"message": "设置内容无效，未写入本机设置。",
		}
	var settings := settings_value as Dictionary
	if not _raw_settings_are_valid(settings):
		return {
			"ok": false,
			"errorCode": "SETTINGS_INVALID",
			"message": "设置内容无效，未写入本机设置。",
		}
	var sanitized := sanitize_settings(settings, settings)
	var config := ConfigFile.new()
	config.set_value(META_SECTION, "schema_version", SCHEMA_VERSION)
	var audio := sanitized.get("audio", {}) as Dictionary
	for key: String in AUDIO_KEYS:
		config.set_value(
			AUDIO_SECTION,
			String(AUDIO_STORAGE_KEYS[key]),
			int(audio.get(key, 0)),
		)
	config.set_value(AUDIO_SECTION, "muted", bool(audio.get("muted", false)))
	var display := sanitized.get("display", {}) as Dictionary
	config.set_value(
		DISPLAY_SECTION,
		"window_mode_id",
		String(display.get("windowModeId", "windowed")),
	)
	config.set_value(
		DISPLAY_SECTION,
		"windowed_resolution_id",
		String(display.get("windowedResolutionId", "1920x1080")),
	)
	config.set_value(
		DISPLAY_SECTION,
		"ui_scale_percent",
		int(display.get("uiScalePercent", 100)),
	)
	config.set_value(
		DISPLAY_SECTION,
		"reduced_flashing_enabled",
		bool(display.get("reducedFlashingEnabled", false)),
	)
	var temporary_path := "%s.tmp" % settings_path
	var backup_path := "%s.bak" % settings_path
	var recovery := _recover_interrupted_replace(
		settings_path,
		backup_path,
		settings,
	)
	if not bool(recovery.get("ok", false)):
		return {
			"ok": false,
			"errorCode": "SETTINGS_SAVE_FAILED",
			"message": "上次设置写入中断，旧设置无法安全恢复。",
			"engineError": recovery.get("engineError", ERR_FILE_CORRUPT),
		}
	_remove_file_if_present(temporary_path)
	var save_error := config.save(temporary_path)
	if save_error != OK:
		return {
			"ok": false,
			"errorCode": "SETTINGS_SAVE_FAILED",
			"message": "设置暂时无法保存；重启游戏后不会使用这次更改。",
			"engineError": save_error,
		}
	var validation := _validate_temporary_file(temporary_path, sanitized)
	if not bool(validation.get("ok", false)):
		_remove_file_if_present(temporary_path)
		return validation
	var replace_error := _replace_validated_file(
		temporary_path,
		settings_path,
		backup_path,
	)
	if replace_error != OK:
		_remove_file_if_present(temporary_path)
		return {
			"ok": false,
			"errorCode": "SETTINGS_SAVE_FAILED",
			"message": "设置暂时无法保存；原有本机设置仍然保留。",
			"engineError": replace_error,
		}
	return {
		"ok": true,
		"errorCode": "",
		"message": "",
	}


func sanitize_settings(settings: Dictionary, fallback: Dictionary) -> Dictionary:
	var source_audio := settings.get("audio", {}) as Dictionary
	var fallback_audio := fallback.get("audio", {}) as Dictionary
	var audio := {}
	for key: String in AUDIO_KEYS:
		var fallback_percent := clampi(int(fallback_audio.get(key, 0)), 0, 100)
		var value: Variant = source_audio.get(key, fallback_percent)
		audio[key] = (
			clampi(int(round(float(value))), 0, 100)
			if typeof(value) in [TYPE_INT, TYPE_FLOAT]
			else fallback_percent
		)
	var muted_value: Variant = source_audio.get(
		"muted",
		fallback_audio.get("muted", false),
	)
	audio["muted"] = (
		bool(muted_value)
		if typeof(muted_value) == TYPE_BOOL
		else bool(fallback_audio.get("muted", false))
	)

	var source_display := settings.get("display", {}) as Dictionary
	var fallback_display := fallback.get("display", {}) as Dictionary
	var fallback_mode := String(fallback_display.get("windowModeId", "windowed"))
	if fallback_mode not in WINDOW_MODE_IDS:
		fallback_mode = "windowed"
	var mode_id := String(source_display.get("windowModeId", fallback_mode))
	if mode_id not in WINDOW_MODE_IDS:
		mode_id = fallback_mode
	var fallback_resolution := _valid_resolution_or(
		String(fallback_display.get("windowedResolutionId", "")),
		"1920x1080",
	)
	var resolution_id := _valid_resolution_or(
		String(source_display.get("windowedResolutionId", "")),
		fallback_resolution,
	)
	var fallback_scale := int(fallback_display.get("uiScalePercent", 100))
	if fallback_scale not in UI_SCALE_PERCENTS:
		fallback_scale = 100
	var scale_value: Variant = source_display.get("uiScalePercent", fallback_scale)
	var ui_scale_percent := (
		int(round(float(scale_value)))
		if typeof(scale_value) in [TYPE_INT, TYPE_FLOAT]
		else fallback_scale
	)
	if ui_scale_percent not in UI_SCALE_PERCENTS:
		ui_scale_percent = fallback_scale
	var reduced_value: Variant = source_display.get(
		"reducedFlashingEnabled",
		fallback_display.get("reducedFlashingEnabled", false),
	)
	var reduced_flashing := (
		bool(reduced_value)
		if typeof(reduced_value) == TYPE_BOOL
		else bool(fallback_display.get("reducedFlashingEnabled", false))
	)
	return {
		"audio": audio,
		"display": {
			"windowModeId": mode_id,
			"windowedResolutionId": resolution_id,
			"uiScalePercent": ui_scale_percent,
			"reducedFlashingEnabled": reduced_flashing,
		},
	}


func _resolution_id_is_valid(resolution_id: String) -> bool:
	var pieces := resolution_id.split("x")
	if pieces.size() != 2 or not pieces[0].is_valid_int() or not pieces[1].is_valid_int():
		return false
	var width := int(pieces[0])
	var height := int(pieces[1])
	return (
		resolution_id == "%dx%d" % [width, height]
		and width >= 640
		and height >= 360
		and width <= 7680
		and height <= 4320
	)


func _valid_resolution_or(resolution_id: String, fallback: String) -> String:
	return resolution_id if _resolution_id_is_valid(resolution_id) else fallback


func _raw_settings_are_valid(settings: Dictionary) -> bool:
	if not _keys_match(settings, SETTINGS_KEYS):
		return false
	var audio_value: Variant = settings.get("audio")
	if typeof(audio_value) != TYPE_DICTIONARY:
		return false
	var audio := audio_value as Dictionary
	if not _keys_match(audio, AUDIO_DATA_KEYS):
		return false
	for key: String in AUDIO_KEYS:
		var value: Variant = audio.get(key)
		if typeof(value) != TYPE_INT:
			return false
		var percent := int(value)
		if percent < 0 or percent > 100:
			return false
	if typeof(audio.get("muted")) != TYPE_BOOL:
		return false
	var display_value: Variant = settings.get("display")
	if typeof(display_value) != TYPE_DICTIONARY:
		return false
	var display := display_value as Dictionary
	if not _keys_match(display, DISPLAY_DATA_KEYS):
		return false
	var mode_value: Variant = display.get("windowModeId")
	if typeof(mode_value) != TYPE_STRING or String(mode_value) not in WINDOW_MODE_IDS:
		return false
	var resolution_value: Variant = display.get("windowedResolutionId")
	if (
		typeof(resolution_value) != TYPE_STRING
		or not _resolution_id_is_valid(String(resolution_value))
	):
		return false
	var scale_value: Variant = display.get("uiScalePercent")
	if typeof(scale_value) != TYPE_INT:
		return false
	if int(scale_value) not in UI_SCALE_PERCENTS:
		return false
	return typeof(display.get("reducedFlashingEnabled")) == TYPE_BOOL


func _config_shape_is_valid(config: ConfigFile) -> bool:
	return (
		_string_keys_match(config.get_sections(), CONFIG_SECTIONS)
		and _string_keys_match(config.get_section_keys(META_SECTION), META_STORAGE_KEYS)
		and _string_keys_match(config.get_section_keys(AUDIO_SECTION), AUDIO_STORAGE_FIELD_KEYS)
		and _string_keys_match(config.get_section_keys(DISPLAY_SECTION), DISPLAY_STORAGE_KEYS)
	)


func _keys_match(value: Dictionary, expected: Array) -> bool:
	if value.size() != expected.size():
		return false
	for key: Variant in expected:
		if not value.has(key):
			return false
	return true


func _string_keys_match(value: PackedStringArray, expected: Array) -> bool:
	if value.size() != expected.size():
		return false
	for key: Variant in expected:
		if String(key) not in value:
			return false
	return true


func _validate_temporary_file(path: String, expected: Dictionary) -> Dictionary:
	var verification := ConfigFile.new()
	var load_error := verification.load(path)
	if load_error != OK:
		return {
			"ok": false,
			"errorCode": "SETTINGS_SAVE_VALIDATION_FAILED",
			"message": "设置写入后无法重新读取；原有本机设置仍然保留。",
			"engineError": load_error,
		}
	if not _config_shape_is_valid(verification):
		return {
			"ok": false,
			"errorCode": "SETTINGS_SAVE_VALIDATION_FAILED",
			"message": "设置写入结构校验不一致；原有本机设置仍然保留。",
			"engineError": ERR_FILE_CORRUPT,
		}
	var schema_value: Variant = verification.get_value(META_SECTION, "schema_version", null)
	if typeof(schema_value) != TYPE_INT or int(schema_value) != SCHEMA_VERSION:
		return {
			"ok": false,
			"errorCode": "SETTINGS_SAVE_VALIDATION_FAILED",
			"message": "设置写入版本校验不一致；原有本机设置仍然保留。",
			"engineError": ERR_FILE_CORRUPT,
		}
	var loaded := {
		"audio": {},
		"display": {},
	}
	var loaded_audio := loaded["audio"] as Dictionary
	var expected_audio := expected.get("audio", {}) as Dictionary
	for key: String in AUDIO_KEYS:
		loaded_audio[key] = verification.get_value(
			AUDIO_SECTION,
			String(AUDIO_STORAGE_KEYS[key]),
			expected_audio.get(key, 0),
		)
	loaded_audio["muted"] = verification.get_value(
		AUDIO_SECTION,
		"muted",
		expected_audio.get("muted", false),
	)
	var loaded_display := loaded["display"] as Dictionary
	var expected_display := expected.get("display", {}) as Dictionary
	loaded_display["windowModeId"] = verification.get_value(
		DISPLAY_SECTION,
		"window_mode_id",
		expected_display.get("windowModeId", "windowed"),
	)
	loaded_display["windowedResolutionId"] = verification.get_value(
		DISPLAY_SECTION,
		"windowed_resolution_id",
		expected_display.get("windowedResolutionId", "1920x1080"),
	)
	loaded_display["uiScalePercent"] = verification.get_value(
		DISPLAY_SECTION,
		"ui_scale_percent",
		expected_display.get("uiScalePercent", 100),
	)
	loaded_display["reducedFlashingEnabled"] = verification.get_value(
		DISPLAY_SECTION,
		"reduced_flashing_enabled",
		expected_display.get("reducedFlashingEnabled", false),
	)
	if not _raw_settings_are_valid(loaded):
		return {
			"ok": false,
			"errorCode": "SETTINGS_SAVE_VALIDATION_FAILED",
			"message": "设置写入原始类型校验不一致；原有本机设置仍然保留。",
			"engineError": ERR_FILE_CORRUPT,
		}
	if loaded != expected:
		return {
			"ok": false,
			"errorCode": "SETTINGS_SAVE_VALIDATION_FAILED",
			"message": "设置写入校验不一致；原有本机设置仍然保留。",
			"engineError": ERR_FILE_CORRUPT,
		}
	return {"ok": true}


func _replace_validated_file(
	temporary_path: String,
	final_path: String,
	backup_path: String,
) -> Error:
	var temporary_absolute := ProjectSettings.globalize_path(temporary_path)
	var final_absolute := ProjectSettings.globalize_path(final_path)
	var backup_absolute := ProjectSettings.globalize_path(backup_path)
	var had_final := FileAccess.file_exists(final_path)
	_remove_file_if_present(backup_path)
	if had_final:
		var backup_error := DirAccess.rename_absolute(final_absolute, backup_absolute)
		if backup_error != OK:
			return backup_error
	var replace_error := DirAccess.rename_absolute(temporary_absolute, final_absolute)
	if replace_error != OK:
		if had_final and FileAccess.file_exists(backup_path):
			DirAccess.rename_absolute(backup_absolute, final_absolute)
		return replace_error
	_remove_file_if_present(backup_path)
	return OK


func _recover_interrupted_replace(
	final_path: String,
	backup_path: String,
	fallback: Dictionary,
) -> Dictionary:
	if not FileAccess.file_exists(backup_path):
		return {"ok": true}
	if FileAccess.file_exists(final_path):
		var current := _load_settings_file(final_path, fallback)
		if (
			bool(current.get("ok", false))
			and bool(current.get("found", false))
		):
			_remove_file_if_present(backup_path)
			_remove_file_if_present("%s.tmp" % final_path)
			return {"ok": true}
	var backup := _load_settings_file(backup_path, fallback)
	if (
		not bool(backup.get("ok", false))
		or not bool(backup.get("found", false))
	):
		return {
			"ok": false,
			"engineError": ERR_FILE_CORRUPT,
		}
	if FileAccess.file_exists(final_path):
		var remove_error := DirAccess.remove_absolute(
			ProjectSettings.globalize_path(final_path),
		)
		if remove_error != OK:
			return {
				"ok": false,
				"engineError": remove_error,
			}
	var rename_error := DirAccess.rename_absolute(
		ProjectSettings.globalize_path(backup_path),
		ProjectSettings.globalize_path(final_path),
	)
	if rename_error != OK:
		return {
			"ok": false,
			"engineError": rename_error,
		}
	var restored := _load_settings_file(final_path, fallback)
	if (
		not bool(restored.get("ok", false))
		or restored.get("settings") != backup.get("settings")
	):
		return {
			"ok": false,
			"engineError": ERR_FILE_CORRUPT,
		}
	_remove_file_if_present("%s.tmp" % final_path)
	return {"ok": true}


func _remove_file_if_present(path: String) -> void:
	if not FileAccess.file_exists(path):
		return
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
