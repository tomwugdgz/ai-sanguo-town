class_name TownWorldContract
extends RefCounted
## 世界对表现层/集成层的最小边界契约(批次B之2)。只声明边界实际调用的方法;
## TownWorldRuntime extends 本类并全部覆写——缺省实现只在世界漂移(删方法)时
## 触发,push_error 会被测试的引擎错误检测抓红。测试替身迁移到本契约按批次 G
## 逐场点审计 has_method 语义后进行。


func abort_restore_candidate(token: String) -> Dictionary:
	push_error("TownWorldContract.abort_restore_candidate 未实现")
	return {}


func abort_save_candidate(token: String) -> Dictionary:
	push_error("TownWorldContract.abort_save_candidate 未实现")
	return {}


func cleanup_restore_candidate(token: String) -> Dictionary:
	push_error("TownWorldContract.cleanup_restore_candidate 未实现")
	return {}


func cleanup_save_candidate(token: String) -> Dictionary:
	push_error("TownWorldContract.cleanup_save_candidate 未实现")
	return {}


func confirm_resident_death(
	resident_ref: String,
	reason: String,
	expected_lifecycle_revision: int = -1,
	expected_world_instance_token: String = "",
) -> Dictionary:
	push_error("TownWorldContract.confirm_resident_death 未实现")
	return {}


func get_active_conversations() -> Array[Dictionary]:
	push_error("TownWorldContract.get_active_conversations 未实现")
	return []


func get_agent_initialization_by_id(resident_id: String) -> Dictionary:
	push_error("TownWorldContract.get_agent_initialization_by_id 未实现")
	return {}


func get_all_place_details() -> Array[Dictionary]:
	push_error("TownWorldContract.get_all_place_details 未实现")
	return []


func get_all_resident_states() -> Array[Dictionary]:
	push_error("TownWorldContract.get_all_resident_states 未实现")
	return []


func get_announcements() -> Array[Dictionary]:
	push_error("TownWorldContract.get_announcements 未实现")
	return []


func get_conversation(conversation_id: String) -> Dictionary:
	push_error("TownWorldContract.get_conversation 未实现")
	return {}


func get_dynamic_prop_snapshot() -> Array[Dictionary]:
	push_error("TownWorldContract.get_dynamic_prop_snapshot 未实现")
	return []


func get_lifecycle_state() -> Dictionary:
	push_error("TownWorldContract.get_lifecycle_state 未实现")
	return {}


func get_place_connection_id(place_name: String) -> String:
	push_error("TownWorldContract.get_place_connection_id 未实现")
	return ""


func get_place_detail(place_name: String) -> Dictionary:
	push_error("TownWorldContract.get_place_detail 未实现")
	return {}


func get_place_names() -> Array[String]:
	push_error("TownWorldContract.get_place_names 未实现")
	return []


func get_player_avatar_state() -> Dictionary:
	push_error("TownWorldContract.get_player_avatar_state 未实现")
	return {}


func get_public_conflict_projection() -> Dictionary:
	push_error("TownWorldContract.get_public_conflict_projection 未实现")
	return {}


func get_public_social_matter_activity() -> Dictionary:
	push_error("TownWorldContract.get_public_social_matter_activity 未实现")
	return {}


func get_resident_action_phase(resident_ref: String) -> Dictionary:
	push_error("TownWorldContract.get_resident_action_phase 未实现")
	return {}


func get_resident_detail(resident_ref: String) -> Dictionary:
	push_error("TownWorldContract.get_resident_detail 未实现")
	return {}


func get_resident_identity_snapshot() -> Dictionary:
	push_error("TownWorldContract.get_resident_identity_snapshot 未实现")
	return {}


func get_resident_movement_snapshot(resident_ref: String) -> Dictionary:
	push_error("TownWorldContract.get_resident_movement_snapshot 未实现")
	return {}


func get_resident_public_relationship_progress(
	resident_ref: String,
) -> Dictionary:
	push_error("TownWorldContract.get_resident_public_relationship_progress 未实现")
	return {}


func get_resident_state(resident_ref: String) -> Dictionary:
	push_error("TownWorldContract.get_resident_state 未实现")
	return {}


func get_simulation_speed() -> int:
	push_error("TownWorldContract.get_simulation_speed 未实现")
	return 0


func get_space_character_movement_contract(space_id: String) -> Dictionary:
	push_error("TownWorldContract.get_space_character_movement_contract 未实现")
	return {}


func get_time() -> Dictionary:
	push_error("TownWorldContract.get_time 未实现")
	return {}


func get_weather() -> String:
	push_error("TownWorldContract.get_weather 未实现")
	return ""


func get_world_log_filter_catalog() -> Dictionary:
	push_error("TownWorldContract.get_world_log_filter_catalog 未实现")
	return {}


func query_world_log_place_observations(
	_place_id: String,
	_options: Dictionary = {},
) -> Dictionary:
	push_error("TownWorldContract.query_world_log_place_observations 未实现")
	return {}


func find_world_log_thread_by_source_event(_event_id: String) -> Dictionary:
	push_error("TownWorldContract.find_world_log_thread_by_source_event 未实现")
	return {}


func get_world_log_causal_chain(
	_thread_id: String,
	_options: Dictionary = {},
) -> Dictionary:
	push_error("TownWorldContract.get_world_log_causal_chain 未实现")
	return {}


func get_world_log_thread_detail(
	thread_id: String,
	options: Dictionary = {},
) -> Dictionary:
	push_error("TownWorldContract.get_world_log_thread_detail 未实现")
	return {}


func get_world_revision() -> int:
	push_error("TownWorldContract.get_world_revision 未实现")
	return 0


func is_paused() -> bool:
	push_error("TownWorldContract.is_paused 未实现")
	return false


func mark_social_candidate_terminal(
	matter_id: String,
	resident_ref: String,
	reason: String,
	expected_response_round_id: String = "",
) -> Dictionary:
	push_error("TownWorldContract.mark_social_candidate_terminal 未实现")
	return {}


func mark_world_log_thread_read(
	thread_id: String,
	displayed_through_sequence: int,
) -> Dictionary:
	push_error("TownWorldContract.mark_world_log_thread_read 未实现")
	return {}


func query_world_log_threads(filters: Dictionary = {}) -> Dictionary:
	push_error("TownWorldContract.query_world_log_threads 未实现")
	return {}


func redispatch_decision_request_by_id(resident_id: String, decision_id: String) -> bool:
	push_error("TownWorldContract.redispatch_decision_request_by_id 未实现")
	return false


func set_simulation_speed(speed: int) -> Dictionary:
	push_error("TownWorldContract.set_simulation_speed 未实现")
	return {}


func set_weather(weather: String) -> Dictionary:
	push_error("TownWorldContract.set_weather 未实现")
	return {}


func submit_agent_decision_by_id(resident_id: String, decision: Dictionary) -> Dictionary:
	push_error("TownWorldContract.submit_agent_decision_by_id 未实现")
	return {}


func submit_avatar_area_attack(intent: Dictionary) -> Dictionary:
	push_error("TownWorldContract.submit_avatar_area_attack 未实现")
	return {}


func take_pending_decision_requests_by_ids(resident_ids: Array) -> Array[Dictionary]:
	push_error("TownWorldContract.take_pending_decision_requests_by_ids 未实现")
	return []


func update_resident_profile(
	resident_ref: String,
	profile: Dictionary,
) -> Dictionary:
	push_error("TownWorldContract.update_resident_profile 未实现")
	return {}


func upsert_animal_presence(state: Dictionary) -> Dictionary:
	push_error("TownWorldContract.upsert_animal_presence 未实现")
	return {}


func upsert_dynamic_prop(
	prop_id: String,
	display_name: String,
	position: Vector2,
	active: bool = true,
) -> Dictionary:
	push_error("TownWorldContract.upsert_dynamic_prop 未实现")
	return {}
