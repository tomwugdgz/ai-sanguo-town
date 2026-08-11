extends SceneTree


const PAGE_SCENE := preload(
	"res://ui/custom_resident_creator/CustomResidentCreatorScreen.tscn"
)
const CandidatePool := preload(
	"res://world/presentation/session/TownCustomResidentCandidatePool.gd"
)
const CreatorService := preload(
	"res://world/presentation/session/TownCustomResidentCreatorService.gd"
)
const ResidentCatalog := preload(
	"res://world/presentation/session/TownResidentCatalog.gd"
)
const WORLD_PATH := "res://world/data/town/town_world.json"

var _failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	root.size = Vector2i(1920, 1080)
	var pool := CandidatePool.new()
	var catalog := ResidentCatalog.load_catalog() as Dictionary
	var world_data := _read_json(WORLD_PATH)
	_expect(bool((pool.configure(catalog) as Dictionary).get("ok", false)), "candidate pool configures")
	var service := CreatorService.new()
	_expect(bool((service.configure(pool, catalog, world_data) as Dictionary).get("ok", false)), "creator service configures")
	var page := PAGE_SCENE.instantiate() as Control
	root.add_child(page)
	page.apply_view_model(service.get_view_model())
	await process_frame
	await process_frame
	var snapshot := page.runtime_gate_snapshot() as Dictionary
	_expect(String(snapshot.get("scope", "")) == "custom_resident_creator", "page renders formal scope")
	_expect(bool(snapshot.get("formalReady", false)), "page receives formal runtime data")
	_expect(snapshot.get("genderOptions", []) == ["女", "男"], "page exposes exactly two genders")
	_expect(bool(snapshot.get("wardrobeEntryPresent", false)), "page renders one complete wardrobe entry")
	_expect(int(snapshot.get("embeddedWardrobeControlCount", -1)) == 0, "page never duplicates wardrobe slot controls")
	_expect(snapshot.get("wardrobeRuntimeSlotOrder", []) == ["hair", "top", "bottom", "shoes"], "wardrobe route keeps the formal runtime contract")
	_expect(String(snapshot.get("contractError", "")).is_empty(), "page contract is valid")
	_expect(not bool(snapshot.get("runtimeMockLoaded", true)), "page never loads runtime mock")
	_expect(not bool(snapshot.get("wholePageScalingUsed", true)), "1920 baseline uses native canvas")
	_expect(
		String(snapshot.get("approvedStructuralShellPath", ""))
		== (
			"res://assets/ui/custom_resident_creator/runtime/shell/"
			+ "custom_resident_creator_structural_shell.png"
		),
		"page uses the user-approved structural shell",
	)
	_expect(
		String(snapshot.get("structuralShellNodeType", "")) == "TextureRect",
		"structural shell remains one page-owned TextureRect",
	)
	_expect(
		int(snapshot.get("programmaticChromeCount", -1)) == 0,
		"page has no programmatic visible chrome",
	)
	_expect(
		String(snapshot.get("pageOwnedControlAssetRoot", ""))
		== "res://assets/ui/custom_resident_creator/runtime/controls/v4/",
		"page uses only its canonical sliced exact-size page-owned control family",
	)
	_expect(
		String(snapshot.get("runtimeAssetManifestPath", ""))
		== (
			"res://assets/ui/custom_resident_creator/runtime/"
			+ "custom_resident_creator_v13_asset_manifest.json"
		),
		"page publishes the user-approved v13 runtime manifest",
	)
	_expect(
		String(snapshot.get("controlSizeContractPath", ""))
		== (
			"res://assets/ui/custom_resident_creator/runtime/controls/v4/"
			+ "control_size_contract.json"
		),
		"page publishes its exact-size control contract",
	)
	_expect(
		not bool(snapshot.get("runtimeConsumesSourceSlices", true)),
		"runtime does not consume source-only transparent slices",
	)
	_expect(
		not bool(snapshot.get("runtimeConsumesChromaSource", true)),
		"runtime does not consume chroma state sheets",
	)
	_expect(
		not bool(snapshot.get("runtimeConsumesAtlas", true)),
		"runtime does not consume an atlas region",
	)
	_expect(
		not bool(snapshot.get("runtimeConsumesCandidateAssets", true)),
		"runtime does not consume candidate or decomposition assets",
	)
	_expect(
		not bool(snapshot.get("runtimeTextureStretch", true)),
		"runtime consumes exact-size control bitmaps without texture resizing",
	)
	_expect(
		String(snapshot.get("focusVisualPolicy", "")) == "hover_or_selected",
		"keyboard focus reuses hover or selected visuals",
	)
	_expect(
		int(snapshot.get("ornamentalFocusAssetCount", -1)) == 0,
		"page exports no ornamental focus frame",
	)
	_expect(
		bool(snapshot.get("exactControlAssetSizing", false)),
		"every visible control bitmap matches its 1920 baseline control rect exactly",
	)
	for contract_value: Variant in snapshot.get("controlAssetContracts", []) as Array:
		var contract := contract_value as Dictionary
		_expect(
			bool(contract.get("exact", false)),
			"%s uses exact-size bitmap %s for control %s" % [
				String(contract.get("name", "control")),
				str(contract.get("textureSize", [])),
				str(contract.get("controlSize", [])),
			],
		)
	_expect(
		bool(snapshot.get("globalDisabledStateVisible", false)),
		"disabled controls use the global gray state logic",
	)
	for target_value: Variant in snapshot.get("touchTargets", []) as Array:
		var target := target_value as Dictionary
		_expect(bool(target.get("minimumMet", false)), "%s meets minimum touch target" % String(target.get("name", "control")))
	var gender_option := page.find_child("GenderOption", true, false) as Button
	_expect(gender_option != null, "gender uses a dropdown field")
	_expect(page.find_child("FemaleButton", true, false) == null, "gender has no female toggle button")
	_expect(page.find_child("MaleButton", true, false) == null, "gender has no male toggle button")
	if gender_option != null:
		gender_option.pressed.emit()
		await process_frame
		await process_frame
		var gender_dropdown_snapshot := page.runtime_gate_snapshot() as Dictionary
		_expect(
			bool(gender_dropdown_snapshot.get("dropdownPopupVisible", false)),
			"gender action opens the dropdown",
		)
		page.call("_close_dropdown_popup", false)
	var occupation_option := page.find_child("OccupationOption", true, false) as Button
	_expect(occupation_option != null, "occupation dropdown field exists")
	var workplace_option := page.find_child("WorkplaceOption", true, false) as Button
	_expect(workplace_option != null and workplace_option.disabled, "occupation-derived workplace remains visible and read-only")
	var interest_option := page.find_child("InterestOption", true, false) as Button
	_expect(interest_option != null and not interest_option.disabled, "former shop asset frame is reused for editable interests")
	if occupation_option != null:
		occupation_option.pressed.emit()
		await process_frame
		await process_frame
		var expanded_snapshot := page.runtime_gate_snapshot() as Dictionary
		_expect(
			bool(expanded_snapshot.get("dropdownPopupImplemented", false)),
			"all work fields use the page-owned expanded dropdown",
		)
		_expect(
			bool(expanded_snapshot.get("dropdownPopupVisible", false)),
			"occupation action opens the expanded dropdown",
		)
		_expect(
			String(expanded_snapshot.get("commonScrollbarAssetId", ""))
			== "ui.common.scrollbar.wood-v1.dropdown-short",
			"expanded dropdown consumes the exact-size common short scrollbar",
		)
		_expect(
			String(expanded_snapshot.get("commonScrollbarManifestPath", ""))
			== (
				"res://assets/ui/common/scrollbar/wood_v1/"
				+ "scrollbar_wood_v1_manifest.json"
			),
			"expanded dropdown publishes the common scrollbar contract",
		)
		_expect(
			not bool(expanded_snapshot.get("dropdownPopupIndividualRowFrames", true)),
			"dropdown options use one panel and separators instead of nested frames",
		)
		_expect(
			bool(expanded_snapshot.get("dropdownScrollbarNativeRangeBinding", false))
			and bool(expanded_snapshot.get("dropdownScrollbarTrackClick", false))
			and bool(expanded_snapshot.get("dropdownScrollbarThumbDrag", false))
			and bool(expanded_snapshot.get("dropdownScrollbarMouseWheel", false)),
			"common scrollbar keeps native wheel, track click and thumb drag semantics",
		)
		_expect(
			(expanded_snapshot.get("dropdownScrollbarThumbVisualSize", []) as Array)
			== [32, 72]
			and (
				expanded_snapshot.get("dropdownScrollbarThumbHitTargetSize", []) as Array
			) == [44, 72],
			"narrow exact-size thumb keeps the larger interaction hit target",
		)
	var name_edit := page.find_child("NameEdit", true, false) as LineEdit
	_expect(name_edit != null, "name field exists for unsaved-exit protection")
	if name_edit != null:
		name_edit.text = "%s（未提交）" % name_edit.text
		_expect(
			bool(page.call("_has_unsaved_profile_changes")),
			"unsubmitted name text is treated as an unsaved change",
		)
		_expect(bool(page.call("request_back")), "unsaved profile handles Escape")
		var unsaved_dialog := (
			page.get_node_or_null("UnsavedProfileConfirmation") as FormalConfirmationDialog
		)
		_expect(
			unsaved_dialog != null and unsaved_dialog.visible,
			"unsaved profile asks before leaving",
		)
	page.queue_free()
	await process_frame
	if _failures.is_empty():
		print("CUSTOM_RESIDENT_CREATOR_RUNTIME_GATE: PASS")
		quit(0)
	else:
		for failure in _failures:
			push_error("CUSTOM_RESIDENT_CREATOR_RUNTIME_GATE: %s" % failure)
		quit(1)


func _read_json(path: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return (parsed as Dictionary).duplicate(true) if parsed is Dictionary else {}


func _expect(condition: bool, description: String) -> void:
	if not condition:
		_failures.append(description)
