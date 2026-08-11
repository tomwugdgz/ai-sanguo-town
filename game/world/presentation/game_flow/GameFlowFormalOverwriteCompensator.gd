class_name GameFlowFormalOverwriteCompensator
extends RefCounted


# 正式档覆盖补偿内核(自 GameFlowHost 下沉):新开局确认覆盖旧档后,若启动失败
# 须把已归档的旧档恢复回来;若启动成功须把归档定稿清理。pending_archive 记录
# "已归档待定稿"的旧档上下文,跨一次启动流程存活。
# 归档服务由调用方解析传入(测试经 host 的 _formal_archive_service_override
# 反射注入,该字段必须留在宿主);_last_result 簿记经 configure 注入的回调,
# 保持原实现的记录点位不变。

const RESULT_SHAPES := preload(
	"res://world/contract/TownWorldResultShapes.gd"
)
var pending_archive: Dictionary = {}

var _record_last_result: Callable = Callable()


func configure(record_last_result: Callable) -> void:
	_record_last_result = record_last_result


func restore_pending(
	startup_failure: Dictionary,
	service: RefCounted,
) -> Dictionary:
	if pending_archive.is_empty():
		return startup_failure.duplicate(true)
	var restore_request := pending_archive.duplicate(true)
	if not service.has_method("restore_completed_new_game_archive"):
		return compensation_failure(
			startup_failure,
			_failure("FORMAL_SLOT_ARCHIVE_RESTORE_CONTRACT_MISSING", false),
			"restore_completed_new_game_archive",
		)
	var restored := service.call(
		"restore_completed_new_game_archive",
		restore_request,
	) as Dictionary
	if not bool(restored.get("ok", false)):
		return compensation_failure(
			startup_failure,
			restored,
			"restore_completed_new_game_archive",
		)
	pending_archive.clear()
	var compensated := startup_failure.duplicate(true)
	compensated["overwriteCompensated"] = true
	compensated["restoredSaveContext"] = (
		restored.get("context", {}) as Dictionary
	).duplicate(true)
	return compensated


func finalize_pending(service: RefCounted) -> Dictionary:
	if pending_archive.is_empty():
		return {
			"ok": true,
			"errorCode": "",
			"retryable": false,
			"changed": false,
		}
	if not service.has_method("finalize_completed_new_game_archive"):
		return _failure(
			"FORMAL_SLOT_ARCHIVE_FINALIZE_CONTRACT_MISSING",
			false,
		)
	var finalized := service.call(
		"finalize_completed_new_game_archive",
		pending_archive.duplicate(true),
	) as Dictionary
	if not bool(finalized.get("ok", false)):
		return finalized
	pending_archive.clear()
	return finalized


func compensation_failure(
	startup_failure: Dictionary,
	failure_detail: Dictionary,
	stage: String,
) -> Dictionary:
	var detail := {
		"stage": stage,
		"startupErrorCode": String(
			startup_failure.get("errorCode", "SESSION_BOOTSTRAP_FAILED"),
		),
		"compensationErrorCode": String(
			failure_detail.get(
				"errorCode",
				"FORMAL_SLOT_ARCHIVE_RESTORE_FAILED",
			),
		),
	}
	var compensation_errors: Variant = failure_detail.get("errors", [])
	if compensation_errors is Array and not (compensation_errors as Array).is_empty():
		detail["compensationErrors"] = (compensation_errors as Array).duplicate(true)
	return _failure(
		"FORMAL_SLOT_OVERWRITE_COMPENSATION_FAILED",
		false,
		[detail],
	)


func recover_interrupted(
	playtest_enabled: bool,
	slot_definitions: Array,
	service: RefCounted,
) -> Dictionary:
	if playtest_enabled:
		return {
			"ok": true,
			"errorCode": "",
			"retryable": false,
			"changed": false,
		}
	if not pending_archive.is_empty():
		var finalized := finalize_pending(service)
		if not bool(finalized.get("ok", false)):
			_record(finalized)
		return finalized
	if not service.has_method("recover_interrupted_new_game_overwrite"):
		return _failure(
			"FORMAL_SLOT_ARCHIVE_RECOVERY_CONTRACT_MISSING",
			false,
		)
	var changed := false
	var recovered_contexts: Array[Dictionary] = []
	for definition_value: Variant in slot_definitions:
		var definition := definition_value as Dictionary
		var slot_id := String(definition.get("slotId", "")).strip_edges()
		if slot_id.is_empty():
			return _failure("STARTUP_SAVE_SLOT_ID_INVALID", false)
		var recovered := service.call(
			"recover_interrupted_new_game_overwrite",
			slot_id,
		) as Dictionary
		if not bool(recovered.get("ok", false)):
			_record(recovered)
			return recovered
		if bool(recovered.get("changed", false)):
			changed = true
		if recovered.get("context") is Dictionary:
			var context := (
				recovered.get("context") as Dictionary
			).duplicate(true)
			if not context.is_empty():
				recovered_contexts.append(context)
	var result := {
		"ok": true,
		"errorCode": "",
		"retryable": false,
		"changed": changed,
	}
	if not recovered_contexts.is_empty():
		result["contexts"] = recovered_contexts
	return result


func _record(result: Dictionary) -> void:
	if _record_last_result.is_valid():
		_record_last_result.call(result)


static func _failure(error_code: String, retryable: bool, errors: Array = []) -> Dictionary:
	return RESULT_SHAPES.failure_with(error_code, retryable, errors)
