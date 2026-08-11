class_name ResidentDetailMeterTrack
extends Control


const UiNodeRetirement := preload("res://ui/common/AiTownUiNodeRetirement.gd")


const TRACK_TEXTURES: Array[Texture2D] = [
	preload(
		"res://assets/ui/resident_detail/"
		+ "runtime/meter_tracks/"
		+ "moss_3_of_5.png"
	),
	preload(
		"res://assets/ui/resident_detail/"
		+ "runtime/meter_tracks/"
		+ "moss_4_of_5.png"
	),
	preload(
		"res://assets/ui/resident_detail/"
		+ "runtime/meter_tracks/"
		+ "honey_3_of_5.png"
	),
	preload(
		"res://assets/ui/resident_detail/"
		+ "runtime/meter_tracks/"
		+ "moss_1_of_5.png"
	),
	preload(
		"res://assets/ui/resident_detail/"
		+ "runtime/meter_tracks/"
		+ "warning_4_of_5.png"
	),
]
const NATIVE_SIZES: Array[Vector2] = [
	Vector2(849, 261),
	Vector2(850, 261),
	Vector2(849, 261),
	Vector2(850, 262),
	Vector2(849, 262),
]
const COMPLETE_PROGRESS_SOURCE: Texture2D = preload(
	"res://assets/ui/resident_detail/"
	+ "runtime/meter_tracks/"
	+ "moss_3_of_5.png"
)
const COMPLETE_PROGRESS_SOURCE_SIZE := Vector2(849.0, 261.0)
const COMPLETE_PROGRESS_FILLED_REGION := Rect2(55.0, 51.0, 146.0, 162.0)
const COMPLETE_PROGRESS_EMPTY_REGION := Rect2(506.0, 51.0, 146.0, 162.0)
const COMPLETE_PROGRESS_CELL_X: Array[float] = [
	55.0,
	205.0,
	356.0,
	506.0,
	657.0,
]

var _texture: TextureRect
var _progress_cells: Array[TextureRect] = []


func _ready() -> void:
	_texture = get_node("Texture") as TextureRect


func configure(
	tone: String,
	segments_filled: int,
	segment_count: int = 5
) -> bool:
	_texture = get_node("Texture") as TextureRect
	_clear_progress_cells()
	if segment_count == 5 and segments_filled >= 0 and segments_filled <= 5:
		var source := COMPLETE_PROGRESS_SOURCE
		var source_size := COMPLETE_PROGRESS_SOURCE_SIZE
		var source_filled_count := 3
		if tone == "attention":
			source = TRACK_TEXTURES[2]
			source_size = NATIVE_SIZES[2]
		elif tone in ["warning", "error"]:
			source = TRACK_TEXTURES[4]
			source_size = NATIVE_SIZES[4]
			source_filled_count = 4
		_texture.texture = source
		_build_complete_progress_cells(
			segments_filled,
			source,
			source_size,
			source_filled_count,
		)
		visible = true
		return true
	var asset_index := _asset_index(
		tone,
		segments_filled,
		segment_count
	)
	if asset_index < 0:
		_texture.texture = null
		visible = false
		return false
	_texture.texture = TRACK_TEXTURES[asset_index]
	visible = true
	return true


func _build_complete_progress_cells(
	segments_filled: int,
	source: Texture2D = COMPLETE_PROGRESS_SOURCE,
	source_size: Vector2 = COMPLETE_PROGRESS_SOURCE_SIZE,
	source_filled_count: int = 3,
) -> void:
	# The approved source contains three filled and two empty cells. First
	# normalize it to the 0/5 state by covering those three filled cells with
	# the source's approved empty cell, then overlay the requested number of
	# approved filled cells. No runtime-drawn borders or colors are introduced.
	var empty_index := clampi(source_filled_count, 0, 4)
	var empty_region := Rect2(
		COMPLETE_PROGRESS_CELL_X[empty_index],
		COMPLETE_PROGRESS_EMPTY_REGION.position.y,
		COMPLETE_PROGRESS_EMPTY_REGION.size.x,
		COMPLETE_PROGRESS_EMPTY_REGION.size.y,
	)
	for index: int in source_filled_count:
		_add_progress_cell(
			empty_region,
			index,
			"EmptyCell_%d" % index,
			source,
			source_size,
		)
	for index: int in segments_filled:
		_add_progress_cell(
			COMPLETE_PROGRESS_FILLED_REGION,
			index,
			"FilledCell_%d" % index,
			source,
			source_size,
		)


func _add_progress_cell(
	source_region: Rect2,
	target_index: int,
	node_name: String,
	source: Texture2D = COMPLETE_PROGRESS_SOURCE,
	source_size: Vector2 = COMPLETE_PROGRESS_SOURCE_SIZE,
) -> void:
	var atlas := AtlasTexture.new()
	atlas.atlas = source
	atlas.region = source_region
	var cell := TextureRect.new()
	cell.name = node_name
	cell.texture = atlas
	cell.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	cell.stretch_mode = TextureRect.STRETCH_SCALE
	cell.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	cell.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cell.position = Vector2(
		COMPLETE_PROGRESS_CELL_X[target_index]
		/ source_size.x
		* size.x,
		source_region.position.y
		/ source_size.y
		* size.y
	).round()
	cell.size = Vector2(
		source_region.size.x
		/ source_size.x
		* size.x,
		source_region.size.y
		/ source_size.y
		* size.y
	).round()
	add_child(cell)
	_progress_cells.append(cell)


func _clear_progress_cells() -> void:
	for cell: TextureRect in _progress_cells:
		if is_instance_valid(cell):
			UiNodeRetirement.retire(cell)
	_progress_cells.clear()


func _asset_index(
	tone: String,
	segments_filled: int,
	segment_count: int
) -> int:
	if segment_count != 5:
		return -1
	if tone in ["warning", "error"] and segments_filled == 4:
		return 4
	if tone == "attention" and segments_filled == 3:
		return 2
	if tone in ["normal", "moss", ""]:
		match segments_filled:
			1:
				return 3
			3:
				return 0
			4:
				return 1
	return -1


func get_component_contract() -> Dictionary:
	var paths: Array[String] = []
	var sizes: Array[Array] = []
	for index: int in TRACK_TEXTURES.size():
		paths.append(TRACK_TEXTURES[index].resource_path)
		sizes.append([
			int(NATIVE_SIZES[index].x),
			int(NATIVE_SIZES[index].y),
		])
	return {
		"componentType": (
			"resident_detail_meter_track_texture"
		),
		"visibleTrackOwner": (
			"ResidentDetailMeterTrack/Texture+EmptyCell_*+FilledCell_*"
		),
		"legacyCellFramesOccluded": true,
		"backgroundCellFramesRemainVisible": false,
		"drawsRuntimeColorRect": false,
		"drawsAdditionalCellBorders": false,
		"fullyComposedStateImages": false,
		"usesApprovedTextureCrops": true,
		"segmentCount": 5,
		"completeNormalProgressRange": [0, 1, 2, 3, 4, 5],
		"completeAttentionProgressRange": [0, 1, 2, 3, 4, 5],
		"completeWarningProgressRange": [0, 1, 2, 3, 4, 5],
		"completeNormalProgressOwner": "approved_moss_cell_texture_crops",
		"completeAttentionProgressOwner": "approved_honey_cell_texture_crops",
		"completeWarningProgressOwner": "approved_warning_cell_texture_crops",
		"drawsProgressWithRuntimeShapes": false,
		"supportedStates": [
			{"tone": "normal", "segmentsFilled": "0..5"},
			{"tone": "attention", "segmentsFilled": "0..5"},
			{"tone": "warning", "segmentsFilled": "0..5"},
		],
		"displaySize": [420, 94],
		"mouseInput": false,
		"assets": paths,
		"nativeSizes": sizes,
	}
