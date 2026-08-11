class_name SystemFeedbackFormalDialog
extends Control


signal action_requested(action_key: StringName)
signal dismiss_requested

const ViewModel := preload(
	"res://ui/common/AiTownUiViewModel.gd"
)
const FormalDialog := preload(
	"res://ui/common/formal_dialog/FormalConfirmationDialog.gd"
)

const ACTION_LABELS := {
	"retry": "重试",
	"end": "结束对话",
	"dismiss": "关闭",
	"confirm": "确认",
	"cancel": "取消",
	"continueObserving": "继续观察",
	"continueEditing": "继续编辑",
	"openSettings": "打开设置",
	"newGame": "进入小镇",
}
const ACTION_ORDER := [
	"retry",
	"confirm",
	"continueObserving",
	"continueEditing",
	"openSettings",
	"newGame",
	"end",
	"dismiss",
	"cancel",
]

@export var reduced_motion := false
@export var expanded := false

var _dialog: FormalConfirmationDialog
var _extra_button: Button
var _view_model: Dictionary = {}
var _feedback: Dictionary = {}
var _action_keys: Array[String] = []
var _extra_action := ""


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_ensure_dialog()


func _ensure_dialog() -> void:
	if _dialog != null:
		return
	_dialog = FormalDialog.new()
	_dialog.name = "FormalDialog"
	_dialog.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_dialog.confirmed.connect(_on_confirmed)
	_dialog.canceled.connect(_on_canceled)
	add_child(_dialog)


func configure(
	view_model: Dictionary,
	_surface_override := "dialog",
) -> PackedStringArray:
	_ensure_dialog()
	var issues := ViewModel.validate(
		view_model,
		"SystemFeedbackFormalDialog"
	)
	if not issues.is_empty():
		return issues
	var data := ViewModel.data_for_render(
		view_model,
		{}
	)
	var feedback_value: Variant = data.get("feedback", null)
	if not feedback_value is Dictionary:
		return PackedStringArray([
			"SystemFeedbackFormalDialog.data.feedback 必须是 Dictionary"
		])
	_view_model = view_model.duplicate(true)
	_feedback = (feedback_value as Dictionary).duplicate(true)
	_action_keys = _enabled_action_keys(view_model)
	_dialog.title = str(_feedback.get("title", "页面没有打开"))
	_dialog.dialog_text = str(
		_feedback.get(
			"message",
			"当前页面暂时无法打开。\n请稍后重试。",
		)
	)
	_dialog.semantic_kind = (
		"error"
		if str(_feedback.get("tone", "error")) == "error"
		else "warning"
	)
	_dialog.cancel_button_text = _action_text(
		_secondary_action(),
		"关闭",
	)
	_dialog.ok_button_text = _action_text(
		_primary_action(),
		"重试",
	)
	_dialog.popup_centered()
	_apply_action_layout()
	return PackedStringArray()


func restore_previous_focus() -> void:
	# SystemFeedbackLayer owns the actual focus snapshot. The formal child has
	# already released its own focus when it was retired.
	pass


func dedupe_identity() -> String:
	var feedback_id := str(_feedback.get("feedbackId", ""))
	if not feedback_id.is_empty():
		return feedback_id
	return (
		str(_view_model.get("scope", ""))
		+ "|"
		+ ViewModel.operation_request_id(_view_model)
		+ "|"
		+ str(ViewModel.operation_status(_view_model))
	)


func request_cancel() -> void:
	_on_canceled()


func _enabled_action_keys(view_model: Dictionary) -> Array[String]:
	var actions := view_model.get("actions", {}) as Dictionary
	var keys: Array[String] = []
	for key: String in ACTION_ORDER:
		if not actions.has(key):
			continue
		var action := actions.get(key, {}) as Dictionary
		if ViewModel.action_enabled(action):
			keys.append(key)
	return keys


func _primary_action() -> String:
	for key: String in _action_keys:
		if key in ["retry", "confirm", "continueObserving", "continueEditing", "openSettings"]:
			return key
	return _action_keys[0] if not _action_keys.is_empty() else ""


func _secondary_action() -> String:
	for key: String in _action_keys:
		if key in ["dismiss", "cancel", "end"]:
			return key
	return _action_keys[1] if _action_keys.size() > 1 else ""


func _extra_actions() -> Array[String]:
	var primary := _primary_action()
	var secondary := _secondary_action()
	var result: Array[String] = []
	for key: String in _action_keys:
		if key in [primary, secondary] or result.has(key):
			continue
		result.append(key)
	return result


func _action_text(key: String, fallback: String) -> String:
	return str(ACTION_LABELS.get(key, fallback)) if not key.is_empty() else fallback


func _apply_action_layout() -> void:
	if _dialog == null:
		return
	var stage := _dialog.get_node_or_null("FormalDialogStage") as Control
	var cancel := _dialog.get_node_or_null(
		"FormalDialogStage/Cancel"
	) as Button
	var confirm := _dialog.get_node_or_null(
		"FormalDialogStage/Confirm"
	) as Button
	if stage == null or cancel == null or confirm == null:
		return
	var extras := _extra_actions()
	_extra_action = extras[0] if not extras.is_empty() else ""
	if _extra_button == null:
		_extra_button = Button.new()
		_extra_button.name = "ExtraAction"
		_extra_button.focus_mode = Control.FOCUS_ALL
		_extra_button.pressed.connect(_on_extra_pressed)
		stage.add_child(_extra_button)
	if _extra_action.is_empty():
		_extra_button.visible = false
		return
	_extra_button.visible = true
	_extra_button.text = _action_text(_extra_action, _extra_action)
	_extra_button.theme = confirm.theme
	for state: StringName in [
		&"normal", &"hover", &"pressed", &"focus", &"disabled"
	]:
		var style := confirm.get_theme_stylebox(state)
		if style != null:
			_extra_button.add_theme_stylebox_override(state, style)
	_extra_button.add_theme_font_override(
		&"font",
		confirm.get_theme_font(&"font"),
	)
	_extra_button.add_theme_font_size_override(
		&"font_size",
		confirm.get_theme_font_size(&"font_size"),
	)
	for color_name: StringName in [
		&"font_color",
		&"font_hover_color",
		&"font_pressed_color",
		&"font_focus_color",
		&"font_disabled_color",
	]:
		_extra_button.add_theme_color_override(
			color_name,
			confirm.get_theme_color(color_name),
		)
	var button_width := 280.0
	var button_y := 468.0
	cancel.position = Vector2(64.0, button_y)
	cancel.size = Vector2(button_width, 82.0)
	_extra_button.position = Vector2(372.0, button_y)
	_extra_button.size = Vector2(button_width, 82.0)
	confirm.position = Vector2(680.0, button_y)
	confirm.size = Vector2(button_width, 82.0)


func _on_confirmed() -> void:
	_emit_action(_primary_action())


func _on_canceled() -> void:
	_emit_action(_secondary_action())


func _on_extra_pressed() -> void:
	_emit_action(_extra_action)


func _emit_action(action_key: String) -> void:
	_dialog.visible = false
	visible = false
	if not action_key.is_empty():
		action_requested.emit(StringName(action_key))
	dismiss_requested.emit()
