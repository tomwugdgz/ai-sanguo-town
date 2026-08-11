class_name TownUiIntentScopeTable
extends RefCounted
## UI intent -> scope 的单一路由表(批次D之2)。取代 Adapter/Projection 两份
## 漂移副本;内容逐字保留前门(TownUiAdapter)语义——两份旧表的全部差异经
## 可达性核查均不可达(见决策点1的枚举),对外行为零变化。


static func scope_for_intent(intent: String) -> String:
	if (
		intent.begins_with("weather_control.")
		or intent.begins_with("environment.weather_")
		or intent == "avatar.switch_to_overview"
	):
		return "weather_control"
	if intent.begins_with("resident_detail."):
		return "resident_detail"
	if intent.begins_with("inner_observation."):
		return "inner_observation"
	if intent.begins_with("resident_overview."):
		return "resident_overview"
	if intent.begins_with("place_focus."):
		return "place_focus"
	if (
		intent == "resident.follow"
		or intent == "resident.action_menu.close"
		or intent == "resident.detail.open"
		or intent == "resident.inner_observation.open"
		or intent == "resident.death.confirm"
	):
		return "resident_action_menu"
	if intent.begins_with("indoor."):
		return "indoor"
	if intent.begins_with("town_log."):
		return "town_log"
	if intent.begins_with("wardrobe."):
		return "wardrobe"
	if intent.begins_with("audio_display_settings."):
		return "audio_display_settings"
	if intent.begins_with("provider_settings."):
		return "provider_settings"
	if intent.begins_with("custom_resident_creator."):
		return "custom_resident_creator"
	if intent.begins_with("resident_profile_editor."):
		return "custom_resident_creator"
	if intent.begins_with("resident_editor."):
		return "resident_editor"
	if intent.begins_with("resident_model_assignment."):
		return "resident_model_assignment"
	if intent.begins_with("pause_menu."):
		return "pause_menu"
	if intent.begins_with("lifecycle."):
		return "lifecycle"
	if intent.begins_with("environment."):
		return "environment"
	if intent.begins_with("announcements."):
		return "announcements"
	if intent.begins_with("conversation."):
		return "conversation"
	if intent.begins_with("avatar."):
		return "avatar"
	if intent.begins_with("town_hud."):
		return "town_hud"
	if intent == "save.create":
		return "save"
	if intent.begins_with("session."):
		return "session"
	return ""
