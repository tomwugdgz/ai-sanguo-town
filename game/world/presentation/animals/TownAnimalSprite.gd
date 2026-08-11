class_name TownAnimalSprite
extends Node2D


const DIRECTION_ROOT := "res://world/presentation/animals/assets/direction_refs/individual"
const CAT_RANDOM_COAT_SHADER := preload(
	"res://world/presentation/animals/CatRandomCoat.gdshader"
)
const BIRD_RANDOM_PALETTE_SHADER := preload(
	"res://world/presentation/animals/BirdRandomPalette.gdshader"
)
const CAT_COAT_PALETTE: Array[Color] = [
	Color("#d27a27"),
	Color("#d7b77a"),
	Color("#9ca1aa"),
	Color("#41464f"),
	Color("#86644d"),
	Color("#5b493b"),
]
const BIRD_COLOR_PALETTES: Array[Array] = [
	[Color("#337fc5"), Color("#f3b82f")],
	[Color("#b9473f"), Color("#efc77e")],
	[Color("#4b8b58"), Color("#e8d37a")],
	[Color("#348e91"), Color("#e99042")],
	[Color("#7666a8"), Color("#efcf75")],
	[Color("#765840"), Color("#d6b979")],
	[Color("#404b59"), Color("#d8d9d3")],
]
const CAT_RIGHT_WALK_PATH := (
	"res://world/presentation/animals/assets/action_frames/cat_right_walk_16f.png"
)
const CAT_LEFT_WALK_PATH := (
	"res://world/presentation/animals/assets/action_frames/cat_left_walk_20f.png"
)
const CAT_FRONT_WALK_PATH := (
	"res://world/presentation/animals/assets/action_frames/cat_front_walk_18f.png"
)
const CAT_BACK_WALK_PATH := (
	"res://world/presentation/animals/assets/action_frames/cat_back_walk_18f.png"
)
const BIRD_FLIGHT_PATH := (
	"res://world/presentation/animals/assets/action_frames/bird_flight_16f.png"
)
const BIRD_LANDING_PATH := (
	"res://world/presentation/animals/assets/action_frames/bird_landing_24f.png"
)
const CAT_RIGHT_FRAME_COUNT := 16
const CAT_LEFT_FRAME_COUNT := 20
const CAT_FRONT_FRAME_COUNT := 18
const CAT_BACK_FRAME_COUNT := 18
const CAT_RIGHT_FRAMES_PER_SECOND := 12.0
const CAT_LEFT_FRAMES_PER_SECOND := 15.0
const CAT_FRONT_FRAMES_PER_SECOND := 13.5
const CAT_BACK_FRAMES_PER_SECOND := 13.5
const BIRD_FLIGHT_FRAME_COUNT := 4
const BIRD_FLIGHT_FRAMES_PER_SECOND := 10.0
const BIRD_LANDING_FRAME_COUNT := 6
const STATIC_SCALE_BY_SPECIES := {
	"cat": 0.34,
	"bird": 0.28,
}
const STATIC_BASELINE_BY_SPECIES := {
	"cat": -42.0,
	"bird": -34.0,
}

var _species := ""
var _sprite: Sprite2D
var _direction_textures: Dictionary = {}
var _cat_right_walk: Texture2D
var _cat_left_walk: Texture2D
var _cat_front_walk: Texture2D
var _cat_back_walk: Texture2D
var _bird_flight: Texture2D
var _bird_landing: Texture2D
var _facing := "right"
var _animation_elapsed := 0.0
var _active_frame := 0
var _petting_bob_phase := 0.0
var _using_walk_frames := false
var _using_flight_frames := false
var _using_landing_frames := false
var _palette_seed := 0.0
var _coat_colors: Array[Color] = []
var _bird_palette_seed := 0.0
var _bird_colors: Array[Color] = []


func configure(
	species: String,
	tint: Color = Color.WHITE,
	color_seed: int = 0,
) -> Dictionary:
	if species not in ["cat", "bird"]:
		return {
			"ok": false,
			"errorCode": "ANIMAL_SPECIES_UNSUPPORTED",
			"errors": ["不支持的小动物种类：%s" % species],
		}
	_species = species
	if _species == "cat":
		_set_cat_coat_seed(color_seed)
	elif _species == "bird":
		_set_bird_palette(color_seed)
	modulate = (
		Color.WHITE
		if _species in ["cat", "bird"]
		else tint
	)
	_load_direction_textures()
	if _species == "cat":
		_cat_right_walk = load(CAT_RIGHT_WALK_PATH) as Texture2D
		_cat_left_walk = load(CAT_LEFT_WALK_PATH) as Texture2D
		_cat_front_walk = load(CAT_FRONT_WALK_PATH) as Texture2D
		_cat_back_walk = load(CAT_BACK_WALK_PATH) as Texture2D
	elif _species == "bird":
		_bird_flight = load(BIRD_FLIGHT_PATH) as Texture2D
		_bird_landing = load(BIRD_LANDING_PATH) as Texture2D
	_build_sprite()
	_show_static_direction(_facing)
	return {
		"ok": true,
		"species": _species,
		"frameCount": (
			CAT_RIGHT_FRAME_COUNT
			if _species == "cat"
			else BIRD_FLIGHT_FRAME_COUNT
			if _species == "bird"
			else 1
		),
		"animationMode": _animation_mode(),
		"colorMode": _color_mode(),
	}


func randomize_cat_coat(color_seed: int) -> Dictionary:
	if _species != "cat":
		return {
			"ok": false,
			"errorCode": "CAT_COAT_ONLY",
		}
	_set_cat_coat_seed(color_seed)
	if _sprite != null and _sprite.material is ShaderMaterial:
		var coat_material := _sprite.material as ShaderMaterial
		coat_material.set_shader_parameter("front_coat_color", _coat_colors[0])
		coat_material.set_shader_parameter("back_coat_color", _coat_colors[1])
		coat_material.set_shader_parameter("patch_coat_color", _coat_colors[2])
		coat_material.set_shader_parameter("pattern_seed", _palette_seed)
	return {
		"ok": true,
		"paletteSeed": _palette_seed,
		"coatColors": _coat_color_hexes(),
	}


func advance(
	delta: float,
	movement: Vector2,
	speed_ratio: float,
	petting: bool,
	airborne: bool = false,
	flight_height: float = 0.0,
	landing_progress: float = -1.0,
) -> void:
	if _sprite == null:
		return
	if movement.length_squared() > 0.0001:
		_facing = _direction_from_vector(movement)
	var moving := speed_ratio > 0.01 and not petting
	if airborne and _species == "bird":
		if landing_progress >= 0.0:
			_active_frame = clampi(
				floori(
					clampf(landing_progress, 0.0, 1.0)
					* float(BIRD_LANDING_FRAME_COUNT)
				),
				0,
				BIRD_LANDING_FRAME_COUNT - 1,
			)
			_show_bird_landing(
				_facing,
				_active_frame,
				flight_height,
			)
		else:
			_animation_elapsed += delta
			_active_frame = (
				floori(_animation_elapsed * BIRD_FLIGHT_FRAMES_PER_SECOND)
				% BIRD_FLIGHT_FRAME_COUNT
			)
			_show_bird_flight(_facing, _active_frame, flight_height)
	elif moving and _species == "cat":
		var frame_count := _walk_frame_count(_facing)
		var frames_per_second := _walk_frames_per_second(_facing)
		_animation_elapsed += delta * lerpf(
			0.82,
			1.12,
			clampf(speed_ratio, 0.0, 1.0),
		)
		_active_frame = (
			floori(_animation_elapsed * frames_per_second)
			% frame_count
		)
		_show_cat_walk(_facing, _active_frame)
	else:
		_active_frame = 0
		_show_static_direction(_facing)
	if petting:
		_petting_bob_phase = fmod(
			_petting_bob_phase + maxf(delta, 0.0) * 9.0,
			TAU,
		)
		_sprite.position.y -= absf(sin(_petting_bob_phase)) * 2.0
	else:
		_petting_bob_phase = 0.0


func get_visual_snapshot() -> Dictionary:
	return {
		"species": _species,
		"animationMode": _animation_mode(),
		"hasSprite2D": _sprite is Sprite2D,
		"hasSkeleton2D": false,
		"direction": _facing,
		"activeFrame": _active_frame,
		"frameCount": (
			BIRD_LANDING_FRAME_COUNT
			if _using_landing_frames
			else BIRD_FLIGHT_FRAME_COUNT
			if _using_flight_frames
			else _walk_frame_count(_facing)
			if _using_walk_frames
			else 1
		),
		"usingWalkFrames": _using_walk_frames,
		"usingFlightFrames": _using_flight_frames,
		"usingLandingFrames": _using_landing_frames,
		"pettingBobPhase": _petting_bob_phase,
		"colorMode": _color_mode(),
		"paletteSeed": (
			_palette_seed
			if _species == "cat"
			else _bird_palette_seed
			if _species == "bird"
			else 0.0
		),
		"coatColors": _coat_color_hexes(),
		"birdColors": _bird_color_hexes(),
		"availableWalkDirections": (
			["front", "right", "back", "left"]
			if _species == "cat"
			else []
		),
		"availableFlightDirections": (
			["front", "right", "back", "left"]
			if _species == "bird"
			else []
		),
	}


func _load_direction_textures() -> void:
	_direction_textures.clear()
	for direction: String in ["front", "right", "back", "left"]:
		var path := "%s/%s_%s.png" % [DIRECTION_ROOT, _species, direction]
		_direction_textures[direction] = load(path) as Texture2D


func _build_sprite() -> void:
	for child: Node in get_children():
		child.queue_free()
	_sprite = Sprite2D.new()
	_sprite.name = "DirectionalSprite"
	_sprite.centered = true
	_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	if _species == "cat":
		var coat_material := ShaderMaterial.new()
		coat_material.shader = CAT_RANDOM_COAT_SHADER
		coat_material.set_shader_parameter("front_coat_color", _coat_colors[0])
		coat_material.set_shader_parameter("back_coat_color", _coat_colors[1])
		coat_material.set_shader_parameter("patch_coat_color", _coat_colors[2])
		coat_material.set_shader_parameter("pattern_seed", _palette_seed)
		_sprite.material = coat_material
	elif _species == "bird":
		var bird_material := ShaderMaterial.new()
		bird_material.shader = BIRD_RANDOM_PALETTE_SHADER
		bird_material.set_shader_parameter("feather_color", _bird_colors[0])
		bird_material.set_shader_parameter("belly_color", _bird_colors[1])
		_sprite.material = bird_material
	add_child(_sprite)


func _show_cat_walk(direction: String, frame_index: int) -> void:
	_using_walk_frames = true
	_using_flight_frames = false
	_using_landing_frames = false
	_sprite.frame = 0
	match direction:
		"left":
			_sprite.texture = _cat_left_walk
			_sprite.hframes = 5
			_sprite.vframes = 4
		"front":
			_sprite.texture = _cat_front_walk
			_sprite.hframes = 6
			_sprite.vframes = 3
		"back":
			_sprite.texture = _cat_back_walk
			_sprite.hframes = 6
			_sprite.vframes = 3
		_:
			_sprite.texture = _cat_right_walk
			_sprite.hframes = 4
			_sprite.vframes = 4
	_sprite.frame = clampi(frame_index, 0, _walk_frame_count(direction) - 1)
	_sprite.flip_h = false
	_sprite.scale = Vector2.ONE * (0.75 if direction in ["front", "back"] else 0.82)
	_sprite.position = Vector2(0.0, -43.0)
	_update_cat_shader_layout(direction, Vector2(128.0, 128.0))


func _show_bird_flight(
	direction: String,
	frame_index: int,
	flight_height: float,
) -> void:
	_using_walk_frames = false
	_using_flight_frames = true
	_using_landing_frames = false
	_sprite.texture = _bird_flight
	_sprite.hframes = 4
	_sprite.vframes = 4
	var row := 0
	match direction:
		"right":
			row = 1
		"back":
			row = 2
		"left":
			row = 3
	_sprite.frame = row * 4 + clampi(frame_index, 0, 3)
	_sprite.flip_h = false
	_sprite.scale = Vector2.ONE * 0.38
	_sprite.position = Vector2(0.0, -48.0 - maxf(flight_height, 0.0))


func _show_bird_landing(
	direction: String,
	frame_index: int,
	flight_height: float,
) -> void:
	_using_walk_frames = false
	_using_flight_frames = true
	_using_landing_frames = true
	_sprite.texture = _bird_landing
	_sprite.hframes = 6
	_sprite.vframes = 4
	var row := 0
	match direction:
		"right":
			row = 1
		"back":
			row = 2
		"left":
			row = 3
	_sprite.frame = row * 6 + clampi(frame_index, 0, 5)
	_sprite.flip_h = false
	_sprite.scale = Vector2.ONE * 0.42
	_sprite.position = Vector2(0.0, -43.0 - maxf(flight_height, 0.0))


func _show_static_direction(direction: String) -> void:
	_using_walk_frames = false
	_using_flight_frames = false
	_using_landing_frames = false
	_sprite.frame = 0
	_sprite.hframes = 1
	_sprite.vframes = 1
	_sprite.texture = _direction_textures.get(direction) as Texture2D
	_sprite.flip_h = false
	var sprite_scale := float(STATIC_SCALE_BY_SPECIES.get(_species, 0.34))
	_sprite.scale = Vector2.ONE * sprite_scale
	_sprite.position = Vector2(
		0.0,
		float(STATIC_BASELINE_BY_SPECIES.get(_species, -42.0)),
	)
	_update_cat_shader_layout(direction, Vector2(288.0, 288.0))


func _animation_mode() -> String:
	if _species == "bird":
		return "Sprite2D directional flight frames"
	return "Sprite2D directional action frames"


func _color_mode() -> String:
	if _species == "cat":
		return "seeded mixed coat"
	if _species == "bird":
		return "seeded natural bird palette"
	return "tint"


func _direction_from_vector(direction: Vector2) -> String:
	if absf(direction.x) > absf(direction.y):
		return "right" if direction.x >= 0.0 else "left"
	return "front" if direction.y >= 0.0 else "back"


func _walk_frame_count(direction: String) -> int:
	match direction:
		"left":
			return CAT_LEFT_FRAME_COUNT
		"front":
			return CAT_FRONT_FRAME_COUNT
		"back":
			return CAT_BACK_FRAME_COUNT
		_:
			return CAT_RIGHT_FRAME_COUNT


func _walk_frames_per_second(direction: String) -> float:
	match direction:
		"left":
			return CAT_LEFT_FRAMES_PER_SECOND
		"front":
			return CAT_FRONT_FRAMES_PER_SECOND
		"back":
			return CAT_BACK_FRAMES_PER_SECOND
		_:
			return CAT_RIGHT_FRAMES_PER_SECOND


func _configure_cat_coat_colors(color_seed: int) -> void:
	_coat_colors.clear()
	var palette_size := CAT_COAT_PALETTE.size()
	var front_index := color_seed % palette_size
	var quotient := floori(float(color_seed) / float(palette_size))
	var back_offset := 1 + quotient % (palette_size - 1)
	var back_index := (front_index + back_offset) % palette_size
	var patch_offset := 1 + floori(float(quotient) / float(palette_size)) % (palette_size - 1)
	var patch_index := (back_index + patch_offset) % palette_size
	if patch_index == front_index:
		patch_index = (patch_index + 1) % palette_size
	_coat_colors.assign([
		CAT_COAT_PALETTE[front_index],
		CAT_COAT_PALETTE[back_index],
		CAT_COAT_PALETTE[patch_index],
	])


func _set_cat_coat_seed(color_seed: int) -> void:
	var positive_color_seed := color_seed % 10007
	if positive_color_seed < 0:
		positive_color_seed += 10007
	_palette_seed = float(positive_color_seed) / 10007.0
	_configure_cat_coat_colors(positive_color_seed)


func _set_bird_palette(color_seed: int) -> void:
	var positive_seed := color_seed % 10007
	if positive_seed < 0:
		positive_seed += 10007
	_bird_palette_seed = float(positive_seed) / 10007.0
	var palette := (
		BIRD_COLOR_PALETTES[
			positive_seed % BIRD_COLOR_PALETTES.size()
		] as Array
	)
	_bird_colors.assign([
		palette[0] as Color,
		palette[1] as Color,
	])


func _coat_color_hexes() -> Array[String]:
	var result: Array[String] = []
	for color: Color in _coat_colors:
		result.append(color.to_html(false))
	return result


func _bird_color_hexes() -> Array[String]:
	var result: Array[String] = []
	for color: Color in _bird_colors:
		result.append(color.to_html(false))
	return result


func _update_cat_shader_layout(direction: String, frame_size: Vector2) -> void:
	if _species != "cat" or not _sprite.material is ShaderMaterial:
		return
	var direction_mode := 0.0
	match direction:
		"left":
			direction_mode = 1.0
		"front":
			direction_mode = 2.0
		"back":
			direction_mode = 3.0
	var coat_material := _sprite.material as ShaderMaterial
	coat_material.set_shader_parameter("direction_mode", direction_mode)
	coat_material.set_shader_parameter("frame_size", frame_size)
