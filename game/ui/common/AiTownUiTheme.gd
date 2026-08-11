class_name AiTownUiTheme
extends RefCounted


const REVISION := "ui.common.system-feedback.style-revision-v2"
const COMMON_APPROVED := true
const FORMAL_READY := true
const THEME_PATH := (
	"res://ui/common/system_feedback/SystemFeedbackTheme.tres"
)


static func shared_theme() -> Theme:
	var theme := ResourceLoader.load(
		THEME_PATH,
		"Theme"
	) as Theme
	if theme == null:
		push_error(
			"无法加载公共 Theme revision %s" % REVISION
		)
	return theme
