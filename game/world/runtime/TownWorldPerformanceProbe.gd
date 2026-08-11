class_name TownWorldPerformanceProbe
extends RefCounted


const ENV_FLAG := "AI_TOWN_UI_FRAME_PROBE"


static func start_lap() -> int:
	return Time.get_ticks_usec() if OS.get_environment(ENV_FLAG) == "1" else 0


static func record_lap(started_usec: int, stage: String) -> int:
	if started_usec <= 0:
		return 0
	var now_usec := Time.get_ticks_usec()
	print("WORLD_PROBE stage=%s usec=%d frame=%d" % [
		stage,
		now_usec - started_usec,
		Engine.get_process_frames(),
	])
	return now_usec
