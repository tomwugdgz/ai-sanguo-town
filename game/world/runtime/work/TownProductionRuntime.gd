class_name TownProductionRuntime
extends RefCounted


const FISHING_REGION_ID := "outdoor_harbor_01"
const GARDEN_REGION_ID := "outdoor_garden_01"
const VALID_WEATHERS := [
	"晴天",
	"阴天",
	"小雨",
	"中雨",
	"大雨",
	"雷暴",
	"下雪",
]
const MAX_FULL_ACCESSIONED_RESEARCH_PROJECTS := 64
const MAX_ARCHIVED_RESEARCH_PROJECTS := 192

var _configured := false
var _last_advanced_minute := 0
var _fishing := {}
var _garden_plots: Dictionary = {}
var _research_sequence := 0
var _research_projects: Dictionary = {}
var _research_archive: Dictionary = {}
var _archived_research_count := 0


func configure(world_data: Dictionary) -> Dictionary:
	if _configured:
		return _failure("PRODUCTION_RUNTIME_ALREADY_CONFIGURED")
	var regions: Dictionary = {}
	for value: Variant in world_data.get("perceptionRegions", []) as Array:
		if value is Dictionary:
			var region := value as Dictionary
			regions[String(region.get("id", ""))] = region
	if (
		not regions.has(FISHING_REGION_ID)
		or not regions.has(GARDEN_REGION_ID)
		or String(
			(regions[FISHING_REGION_ID] as Dictionary).get(
				"placeName",
				"",
			)
		) != "渔港"
		or String(
			(regions[GARDEN_REGION_ID] as Dictionary).get(
				"placeName",
				"",
			)
		) != "社区花园"
	):
		return _failure("PRODUCTION_REGION_INVALID")
	_configured = true
	return {"ok": true, "errorCode": ""}


func initialize(absolute_minute: int) -> Dictionary:
	if not _configured or absolute_minute < 0:
		return _failure("PRODUCTION_RUNTIME_NOT_CONFIGURED")
	_last_advanced_minute = absolute_minute
	_fishing = {
		"regionId": FISHING_REGION_ID,
		"gearAvailable": true,
		"cooldownUntilMinute": absolute_minute,
		"lastAttemptMinute": -1,
		"lastResult": "none",
	}
	_garden_plots = {
		"garden_plot_west": _opening_plot(
			"garden_plot_west",
			72,
			0,
			2,
		),
		"garden_plot_center": _opening_plot(
			"garden_plot_center",
			46,
			1,
			0,
		),
		"garden_plot_east": _opening_plot(
			"garden_plot_east",
			28,
			2,
			0,
		),
	}
	_research_sequence = 0
	_research_projects.clear()
	_research_archive.clear()
	_archived_research_count = 0
	return {"ok": true, "errorCode": ""}


func advance_to(absolute_minute: int, weather: String) -> Dictionary:
	if (
		not _configured
		or absolute_minute < _last_advanced_minute
		or weather not in VALID_WEATHERS
	):
		return _failure("PRODUCTION_ADVANCE_INVALID")
	for minute in range(_last_advanced_minute + 1, absolute_minute + 1):
		if posmod(minute, 120) != 0:
			continue
		for plot_id_value: Variant in _garden_plots:
			var plot := _garden_plots[plot_id_value] as Dictionary
			var raining := weather in ["小雨", "中雨", "大雨", "雷暴"]
			plot["moisture"] = clampi(
				int(plot.get("moisture", 0))
				+ (18 if raining else -12),
				0,
				100,
			)
			if not raining and int(plot.get("moisture", 0)) < 45:
				plot["weedLevel"] = mini(
					3,
					int(plot.get("weedLevel", 0)) + 1,
				)
			var growth := int(plot.get("growth", 0))
			if int(plot.get("moisture", 0)) >= 35:
				growth = mini(100, growth + 8)
			plot["growth"] = growth
			if growth >= 100 and int(plot.get("harvestUnits", 0)) == 0:
				plot["harvestUnits"] = 2
			_garden_plots[String(plot_id_value)] = plot
	_last_advanced_minute = absolute_minute
	return {"ok": true, "errorCode": ""}


func fishing_task_needed(
	absolute_minute: int,
	fish_inventory: int = 0,
) -> bool:
	var minute_of_day := posmod(absolute_minute, 1440)
	return (
		_configured
		and fish_inventory < 3
		and bool(_fishing.get("gearAvailable", false))
		and absolute_minute
			>= int(_fishing.get("cooldownUntilMinute", 0))
		and minute_of_day >= 300
		and minute_of_day < 1140
	)


func resolve_fishing(
	absolute_minute: int,
	weather: String,
) -> Dictionary:
	if (
		not _configured
		or absolute_minute
			< int(_fishing.get("cooldownUntilMinute", 0))
		or weather not in VALID_WEATHERS
	):
		return _failure("FISHING_RESULT_INVALID")
	var unsafe := weather in ["大雨", "雷暴", "下雪"]
	var quantity := 0
	if not unsafe:
		var hour := posmod(absolute_minute, 1440) / 60
		var time_bonus := 1 if hour < 10 or hour >= 16 else 0
		var weather_bonus := 1 if weather in ["阴天", "小雨"] else 0
		quantity = 1 + time_bonus + weather_bonus
	_fishing["lastAttemptMinute"] = absolute_minute
	_fishing["lastResult"] = "catch" if quantity > 0 else "empty"
	_fishing["cooldownUntilMinute"] = absolute_minute + 180
	return {
		"ok": true,
		"errorCode": "",
		"quantity": quantity,
		"regionId": FISHING_REGION_ID,
		"resultKind": "catch" if quantity > 0 else "empty",
	}


func care_task_plot() -> Dictionary:
	for plot_id: String in _sorted_plot_ids():
		var plot := _garden_plots[plot_id] as Dictionary
		if (
			int(plot.get("moisture", 0)) < 45
			or int(plot.get("weedLevel", 0)) >= 2
		):
			return plot.duplicate(true)
	return {}


func harvest_task_plot() -> Dictionary:
	for plot_id: String in _sorted_plot_ids():
		var plot := _garden_plots[plot_id] as Dictionary
		if int(plot.get("harvestUnits", 0)) > 0:
			return plot.duplicate(true)
	return {}


func resolve_garden_care(plot_id: String) -> Dictionary:
	if not _garden_plots.has(plot_id):
		return _failure("GARDEN_PLOT_UNKNOWN")
	var plot := _garden_plots[plot_id] as Dictionary
	var previous_moisture := int(plot.get("moisture", 0))
	var previous_weeds := int(plot.get("weedLevel", 0))
	if previous_moisture >= 45 and previous_weeds < 2:
		return _failure("GARDEN_CARE_NOT_NEEDED")
	plot["moisture"] = maxi(previous_moisture, 78)
	plot["weedLevel"] = maxi(0, previous_weeds - 2)
	_garden_plots[plot_id] = plot
	return {
		"ok": true,
		"errorCode": "",
		"plot": plot.duplicate(true),
		"resultKind": "garden_state_change",
	}


func resolve_garden_harvest(plot_id: String) -> Dictionary:
	if not _garden_plots.has(plot_id):
		return _failure("GARDEN_PLOT_UNKNOWN")
	var plot := _garden_plots[plot_id] as Dictionary
	var quantity := int(plot.get("harvestUnits", 0))
	if quantity <= 0:
		return _failure("GARDEN_NOT_READY")
	plot["harvestUnits"] = 0
	plot["growth"] = 35
	_garden_plots[plot_id] = plot
	return {
		"ok": true,
		"errorCode": "",
		"plot": plot.duplicate(true),
		"quantity": quantity,
		"resultKind": "flower_lot",
	}


func begin_plant_research(
	question: String,
	source_kind: String,
	requester_resident_id: String,
	absolute_minute: int,
) -> Dictionary:
	var normalized_question := question.strip_edges()
	if (
		not _configured
		or normalized_question.is_empty()
		or normalized_question.length() > 240
		or source_kind not in [
			"research_question",
			"abnormal_plant",
			"season_change",
			"clinic_request",
			"personal_research_plan",
		]
		or absolute_minute < 0
	):
		return _failure("PLANT_RESEARCH_REQUEST_INVALID")
	_research_sequence += 1
	var project_id := "plant-research-%d" % _research_sequence
	var project := {
		"projectId": project_id,
		"question": normalized_question,
		"sourceKind": source_kind,
		"requesterResidentId": requester_resident_id.strip_edges(),
		"stage": "question",
		"createdAtMinute": absolute_minute,
		"updatedAtMinute": absolute_minute,
		"observation": {},
		"verification": {},
		"record": {},
		"accession": {},
	}
	_research_projects[project_id] = project
	return {
		"ok": true,
		"errorCode": "",
		"project": project.duplicate(true),
	}


func record_plant_observation(
	project_id: String,
	worker_resident_id: String,
	weather: String,
	absolute_minute: int,
	region_id := GARDEN_REGION_ID,
	place_id := "社区花园",
	visible_features: Array = [],
) -> Dictionary:
	var project := _research_project_for_stage(
		project_id,
		"question",
	)
	if project.is_empty() or weather not in VALID_WEATHERS:
		return _failure("PLANT_RESEARCH_OBSERVATION_INVALID")
	var normalized_region_id := String(region_id).strip_edges()
	if normalized_region_id.is_empty():
		return _failure("PLANT_RESEARCH_OBSERVATION_INVALID")
	project["stage"] = "observed"
	project["updatedAtMinute"] = absolute_minute
	var observation := {
		"workerResidentId": worker_resident_id,
		"regionId": normalized_region_id,
		"placeId": String(place_id),
		"weather": weather,
		"visibleFeatures": visible_features.duplicate(),
		"observedAtMinute": absolute_minute,
	}
	if normalized_region_id == GARDEN_REGION_ID:
		var plot := _garden_plots.get(
			"garden_plot_center",
			{},
		) as Dictionary
		observation["moisture"] = int(plot.get("moisture", 0))
		observation["weedLevel"] = int(plot.get("weedLevel", 0))
		observation["growth"] = int(plot.get("growth", 0))
	project["observation"] = observation
	_research_projects[project_id] = project
	return {
		"ok": true,
		"errorCode": "",
		"project": project.duplicate(true),
		"resultKind": "research_record",
	}


func record_plant_verification(
	project_id: String,
	worker_resident_id: String,
	absolute_minute: int,
) -> Dictionary:
	var project := _research_project_for_stage(
		project_id,
		"observed",
	)
	if project.is_empty():
		return _failure("PLANT_RESEARCH_VERIFICATION_INVALID")
	project["stage"] = "verified"
	project["updatedAtMinute"] = absolute_minute
	project["verification"] = {
		"workerResidentId": worker_resident_id,
		"placeId": "图书馆",
		"sourceChecked": true,
		"verifiedAtMinute": absolute_minute,
	}
	_research_projects[project_id] = project
	return {
		"ok": true,
		"errorCode": "",
		"project": project.duplicate(true),
		"resultKind": "research_record",
	}


func finish_plant_research_record(
	project_id: String,
	worker_resident_id: String,
	absolute_minute: int,
) -> Dictionary:
	var project := _research_project_for_stage(
		project_id,
		"verified",
	)
	if project.is_empty():
		return _failure("PLANT_RESEARCH_RECORD_INVALID")
	project["stage"] = "recorded"
	project["updatedAtMinute"] = absolute_minute
	project["record"] = {
		"recordId": "research-record:%s" % project_id,
		"workerResidentId": worker_resident_id,
		"question": String(project.get("question", "")),
		"observationConfirmed": not (
			project.get("observation", {}) as Dictionary
		).is_empty(),
		"sourceVerified": bool(
			(project.get("verification", {}) as Dictionary).get(
				"sourceChecked",
				false,
			)
		),
		"writtenAtPlaceId": "图书馆",
		"writtenAtMinute": absolute_minute,
	}
	_research_projects[project_id] = project
	return {
		"ok": true,
		"errorCode": "",
		"project": project.duplicate(true),
		"record": (
			project.get("record", {}) as Dictionary
		).duplicate(true),
		"resultKind": "research_record",
	}


func plant_research_project(project_id: String) -> Dictionary:
	if _research_projects.has(project_id):
		return (
			_research_projects.get(project_id, {}) as Dictionary
		).duplicate(true)
	if _research_archive.has(project_id):
		return (
			_research_archive.get(project_id, {}) as Dictionary
		).duplicate(true)
	return {}


func plant_research_projects() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var project_ids: Array[String] = []
	for project_id_value: Variant in _research_projects:
		project_ids.append(String(project_id_value))
	for project_id_value: Variant in _research_archive:
		project_ids.append(String(project_id_value))
	project_ids.sort()
	for project_id: String in project_ids:
		result.append(plant_research_project(project_id))
	return result


func record_research_accession(
	record_id: String,
	accession: Dictionary,
	absolute_minute: int,
) -> Dictionary:
	for project_id_value: Variant in _research_projects:
		var project_id := String(project_id_value)
		var project := (
			_research_projects.get(project_id, {}) as Dictionary
		).duplicate(true)
		if (
			String(
				(project.get("record", {}) as Dictionary).get(
					"recordId",
					"",
				),
			) != record_id
			or String(project.get("stage", "")) != "recorded"
			or accession.is_empty()
		):
			continue
		project["stage"] = "accessioned"
		project["updatedAtMinute"] = absolute_minute
		project["accession"] = accession.duplicate(true)
		_research_projects[project_id] = project
		_compact_accessioned_research_projects()
		return {
			"ok": true,
			"errorCode": "",
			"project": project.duplicate(true),
		}
	return _failure("PLANT_RESEARCH_ACCESSION_INVALID")


func snapshot() -> Dictionary:
	var plots: Array[Dictionary] = []
	for plot_id: String in _sorted_plot_ids():
		plots.append(
			(_garden_plots[plot_id] as Dictionary).duplicate(true),
		)
	var full_projects: Array[Dictionary] = []
	var full_project_ids: Array[String] = []
	for project_id_value: Variant in _research_projects:
		full_project_ids.append(String(project_id_value))
	full_project_ids.sort()
	for project_id: String in full_project_ids:
		full_projects.append(
			(_research_projects.get(project_id, {}) as Dictionary).duplicate(true),
		)
	var archived_projects: Array[Dictionary] = []
	var archived_project_ids: Array[String] = []
	for project_id_value: Variant in _research_archive:
		archived_project_ids.append(String(project_id_value))
	archived_project_ids.sort()
	for project_id: String in archived_project_ids:
		archived_projects.append(
			(_research_archive.get(project_id, {}) as Dictionary).duplicate(true),
		)
	return {
		"schemaVersion": 1,
		"lastAdvancedMinute": _last_advanced_minute,
		"fishing": _fishing.duplicate(true),
		"gardenPlots": plots,
		"researchSequence": _research_sequence,
		"researchProjects": full_projects,
		"researchArchive": archived_projects,
		"archivedResearchCount": _archived_research_count,
	}


func restore(snapshot_value: Dictionary) -> Dictionary:
	if (
		not _configured
		or snapshot_value.get("schemaVersion") != 1
		or typeof(snapshot_value.get("lastAdvancedMinute")) != TYPE_INT
		or not snapshot_value.get("fishing") is Dictionary
		or not snapshot_value.get("gardenPlots") is Array
		or not snapshot_value.get("researchArchive", []) is Array
		or typeof(snapshot_value.get("archivedResearchCount", 0)) != TYPE_INT
		or int(snapshot_value.get("archivedResearchCount", 0)) < 0
	):
		return _failure("PRODUCTION_SNAPSHOT_INVALID")
	var fishing := snapshot_value.get("fishing", {}) as Dictionary
	if (
		String(fishing.get("regionId", "")) != FISHING_REGION_ID
		or typeof(fishing.get("gearAvailable")) != TYPE_BOOL
		or typeof(fishing.get("cooldownUntilMinute")) != TYPE_INT
		or typeof(fishing.get("lastAttemptMinute")) != TYPE_INT
		or String(fishing.get("lastResult", ""))
			not in ["none", "catch", "empty"]
	):
		return _failure("PRODUCTION_SNAPSHOT_INVALID")
	var plots: Dictionary = {}
	for value: Variant in snapshot_value.get("gardenPlots", []) as Array:
		if not value is Dictionary:
			return _failure("PRODUCTION_SNAPSHOT_INVALID")
		var plot := value as Dictionary
		var plot_id := String(plot.get("plotId", ""))
		if (
			plot_id.is_empty()
			or plots.has(plot_id)
			or String(plot.get("regionId", "")) != GARDEN_REGION_ID
			or typeof(plot.get("moisture")) != TYPE_INT
			or typeof(plot.get("weedLevel")) != TYPE_INT
			or typeof(plot.get("growth")) != TYPE_INT
			or typeof(plot.get("harvestUnits")) != TYPE_INT
		):
			return _failure("PRODUCTION_SNAPSHOT_INVALID")
		plots[plot_id] = plot.duplicate(true)
	if plots.size() != 3:
		return _failure("PRODUCTION_SNAPSHOT_INVALID")
	_last_advanced_minute = int(
		snapshot_value.get("lastAdvancedMinute", 0),
	)
	_fishing = fishing.duplicate(true)
	_garden_plots = plots
	_research_sequence = int(
		snapshot_value.get("researchSequence", 0),
	)
	_research_projects.clear()
	_research_archive.clear()
	var research_projects_value: Variant = snapshot_value.get(
		"researchProjects",
		[],
	)
	if (
		typeof(snapshot_value.get("researchSequence", 0)) != TYPE_INT
		or _research_sequence < 0
		or not research_projects_value is Array
	):
		return _failure("PRODUCTION_SNAPSHOT_INVALID")
	for value: Variant in research_projects_value as Array:
		if not value is Dictionary:
			return _failure("PRODUCTION_SNAPSHOT_INVALID")
		var project := value as Dictionary
		var project_id := String(project.get("projectId", ""))
		if (
			project_id.is_empty()
			or _research_projects.has(project_id)
			or String(project.get("question", "")).strip_edges().is_empty()
			or String(project.get("stage", "")) not in [
				"question",
				"observed",
				"verified",
				"recorded",
				"accessioned",
			]
			or typeof(project.get("createdAtMinute")) != TYPE_INT
			or typeof(project.get("updatedAtMinute")) != TYPE_INT
			or not project.get("observation") is Dictionary
			or not project.get("verification") is Dictionary
			or not project.get("record") is Dictionary
			or (
				project.has("accession")
				and not project.get("accession") is Dictionary
			)
		):
			return _failure("PRODUCTION_SNAPSHOT_INVALID")
		if not project.has("accession"):
			project = project.duplicate(true)
			project["accession"] = {}
		_research_projects[project_id] = project.duplicate(true)
	for value: Variant in snapshot_value.get("researchArchive", []) as Array:
		if not value is Dictionary:
			return _failure("PRODUCTION_SNAPSHOT_INVALID")
		var archived := (value as Dictionary).duplicate(true)
		var project_id := String(archived.get("projectId", ""))
		if (
			project_id.is_empty()
			or _research_projects.has(project_id)
			or _research_archive.has(project_id)
			or String(archived.get("question", "")).strip_edges().is_empty()
			or String(archived.get("stage", "")) != "accessioned"
			or typeof(archived.get("createdAtMinute")) != TYPE_INT
			or typeof(archived.get("updatedAtMinute")) != TYPE_INT
			or not archived.get("record") is Dictionary
			or not archived.get("accession") is Dictionary
		):
			return _failure("PRODUCTION_SNAPSHOT_INVALID")
		_research_archive[project_id] = archived
	_archived_research_count = int(
		snapshot_value.get("archivedResearchCount", 0),
	)
	_compact_accessioned_research_projects()
	return {"ok": true, "errorCode": ""}


func _compact_accessioned_research_projects() -> void:
	var completed: Array[Dictionary] = []
	for value: Variant in _research_projects.values():
		var project := value as Dictionary
		if String(project.get("stage", "")) == "accessioned":
			completed.append(project)
	completed.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if int(a.get("updatedAtMinute", -1)) != int(b.get("updatedAtMinute", -1)):
			return int(a.get("updatedAtMinute", -1)) > int(b.get("updatedAtMinute", -1))
		return String(a.get("projectId", "")) > String(b.get("projectId", ""))
	)
	for index in range(
		MAX_FULL_ACCESSIONED_RESEARCH_PROJECTS,
		completed.size(),
	):
		var project := completed[index] as Dictionary
		var project_id := String(project.get("projectId", ""))
		_research_archive[project_id] = _archived_research_project(project)
		_research_projects.erase(project_id)
	_compact_research_archive()


func _compact_research_archive() -> void:
	var archived: Array[Dictionary] = []
	for value: Variant in _research_archive.values():
		archived.append(value as Dictionary)
	archived.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if int(a.get("updatedAtMinute", -1)) != int(b.get("updatedAtMinute", -1)):
			return int(a.get("updatedAtMinute", -1)) > int(b.get("updatedAtMinute", -1))
		return String(a.get("projectId", "")) > String(b.get("projectId", ""))
	)
	for index in range(MAX_ARCHIVED_RESEARCH_PROJECTS, archived.size()):
		_research_archive.erase(String(archived[index].get("projectId", "")))
		_archived_research_count += 1


func _archived_research_project(project: Dictionary) -> Dictionary:
	return {
		"projectId": String(project.get("projectId", "")),
		"question": String(project.get("question", "")),
		"sourceKind": String(project.get("sourceKind", "")),
		"requesterResidentId": String(
			project.get("requesterResidentId", ""),
		),
		"stage": "accessioned",
		"createdAtMinute": int(project.get("createdAtMinute", 0)),
		"updatedAtMinute": int(project.get("updatedAtMinute", 0)),
		"record": (
			project.get("record", {}) as Dictionary
		).duplicate(true),
		"accession": (
			project.get("accession", {}) as Dictionary
		).duplicate(true),
		"archived": true,
	}


func _opening_plot(
	plot_id: String,
	moisture: int,
	weed_level: int,
	harvest_units: int,
) -> Dictionary:
	return {
		"plotId": plot_id,
		"regionId": GARDEN_REGION_ID,
		"moisture": moisture,
		"weedLevel": weed_level,
		"growth": 100 if harvest_units > 0 else 55,
		"harvestUnits": harvest_units,
	}


func _sorted_plot_ids() -> Array[String]:
	var result: Array[String] = []
	for value: Variant in _garden_plots:
		result.append(String(value))
	result.sort()
	return result


func _research_project_for_stage(
	project_id: String,
	stage: String,
) -> Dictionary:
	if not _research_projects.has(project_id):
		return {}
	var project := (
		_research_projects.get(project_id, {}) as Dictionary
	).duplicate(true)
	if String(project.get("stage", "")) != stage:
		return {}
	return project


func _failure(error_code: String) -> Dictionary:
	return {"ok": false, "errorCode": error_code}
