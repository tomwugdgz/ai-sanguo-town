class_name ResidentDeathDissolveEffect
extends Node2D


signal finished


const DURATION_SECONDS := 1.05
const EMIT_DELAY_SECONDS := 0.28
const PARTICLE_COUNT := 42

var _elapsed := 0.0
var _particles: Array[Dictionary] = []
var _running := false


func _ready() -> void:
	visible = false
	set_process(false)


func start(resident_id: String) -> void:
	if _running:
		return
	_running = true
	_elapsed = 0.0
	_particles = _build_particles(resident_id)
	visible = true
	set_process(true)
	queue_redraw()


func cancel() -> void:
	_running = false
	_elapsed = 0.0
	_particles.clear()
	visible = false
	set_process(false)
	queue_redraw()


func _process(delta: float) -> void:
	if not _running:
		return
	_elapsed += maxf(delta, 0.0)
	queue_redraw()
	if _elapsed < DURATION_SECONDS:
		return
	_running = false
	visible = false
	set_process(false)
	finished.emit()


func _draw() -> void:
	if not _running or _elapsed < EMIT_DELAY_SECONDS:
		return
	var progress := clampf(
		(_elapsed - EMIT_DELAY_SECONDS)
		/ (DURATION_SECONDS - EMIT_DELAY_SECONDS),
		0.0,
		1.0,
	)
	for particle: Dictionary in _particles:
		var delay := float(particle.get("delay", 0.0))
		var local_progress := clampf(
			(progress - delay) / maxf(1.0 - delay, 0.01),
			0.0,
			1.0,
		)
		if local_progress <= 0.0:
			continue
		var start := particle.get("start", Vector2.ZERO) as Vector2
		var drift := particle.get("drift", Vector2.ZERO) as Vector2
		var particle_position := start + drift * local_progress
		particle_position.y -= 18.0 * local_progress * local_progress
		particle_position = particle_position.round()
		var size := float(particle.get("size", 4.0))
		var tone := float(particle.get("tone", 0.72))
		var alpha := clampf(
			(1.0 - local_progress) * minf(local_progress * 5.0, 1.0),
			0.0,
			1.0,
		)
		draw_rect(
			Rect2(particle_position, Vector2(size, size)),
			Color(tone, tone, tone, alpha),
		)


func _build_particles(resident_id: String) -> Array[Dictionary]:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(resident_id)
	var result: Array[Dictionary] = []
	for index in PARTICLE_COUNT:
		var vertical_ratio := float(index) / float(PARTICLE_COUNT - 1)
		result.append({
			"start": Vector2(
				rng.randf_range(-48.0, 48.0),
				lerpf(-205.0, -12.0, vertical_ratio)
				+ rng.randf_range(-10.0, 10.0),
			),
			"drift": Vector2(
				rng.randf_range(-34.0, 34.0),
				rng.randf_range(-24.0, 20.0),
			),
			"delay": rng.randf_range(0.0, 0.42),
			"size": float(rng.randi_range(4, 8)),
			"tone": rng.randf_range(0.56, 0.88),
		})
	return result
