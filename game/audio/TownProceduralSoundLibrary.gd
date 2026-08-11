extends RefCounted


const DEFAULT_MIX_RATE := 48000
const AMBIENCE_MIX_RATE := 24000
const AMBIENCE_SECONDS := 8.0


static func build_cues(
	mix_rate: int = DEFAULT_MIX_RATE,
	cue_ids: Array = [],
) -> Dictionary:
	var cues: Dictionary = {}
	var specs := _cue_specs()
	for cue_id: String in specs:
		if not cue_ids.is_empty() and not cue_ids.has(cue_id):
			continue
		cues[cue_id] = build_cue(cue_id, mix_rate)
	return cues


static func build_cue(
	cue_id: String,
	mix_rate: int = DEFAULT_MIX_RATE,
) -> AudioStreamWAV:
	var spec := _cue_specs().get(cue_id, {}) as Dictionary
	if spec.is_empty():
		return null
	return _make_cue(
		cue_id,
		float(spec.get("duration", 0.12)),
		spec.get("hits", []) as Array,
		mix_rate,
	)


static func build_ambiences() -> Dictionary:
	return {
		"day": _make_ambience("day"),
		"night": _make_ambience("night"),
		"indoor": _make_ambience("indoor"),
	}


static func build_ambience(kind: String) -> AudioStreamWAV:
	if kind not in ["day", "night", "indoor"]:
		return null
	return _make_ambience(kind)


static func _cue_specs() -> Dictionary:
	return {
		"ui_tap": _spec(0.055, [_hit(0.0, 850.0, 0.19, "tile")]),
		"ui_select": _spec(0.09, [
			_hit(0.0, 720.0, 0.16, "tile"),
			_hit(0.027, 940.0, 0.07, "chime"),
		]),
		"ui_deselect": _spec(0.09, [
			_hit(0.0, 750.0, 0.13, "tile"),
			_hit(0.03, 570.0, 0.06, "chime"),
		]),
		"ui_back": _spec(0.085, [
			_hit(0.0, 660.0, 0.16, "tile"),
			_hit(0.032, 520.0, 0.07, "chime"),
		]),
		"ui_page": _spec(0.14, [
			_hit(0.0, 1550.0, 0.15, "paper"),
			_hit(0.042, 920.0, 0.07, "tile"),
		]),
		"ui_tab": _spec(0.075, [_hit(0.0, 700.0, 0.18, "wood")]),
		"ui_toggle_on": _spec(0.12, [
			_hit(0.0, 700.0, 0.14, "wood"),
			_hit(0.042, 1020.0, 0.07, "chime"),
		]),
		"ui_toggle_off": _spec(0.12, [
			_hit(0.0, 700.0, 0.14, "wood"),
			_hit(0.042, 500.0, 0.06, "chime"),
		]),
		"ui_slider": _spec(0.045, [_hit(0.0, 1040.0, 0.12, "tile")]),
		"ui_confirm": _spec(0.16, [
			_hit(0.0, 760.0, 0.16, "tile"),
			_hit(0.058, 980.0, 0.17, "tile"),
			_hit(0.062, 1280.0, 0.04, "chime"),
		]),
		"ui_success": _spec(0.3, [
			_hit(0.0, 660.0, 0.08, "chime"),
			_hit(0.085, 830.0, 0.09, "chime"),
			_hit(0.17, 1080.0, 0.10, "chime"),
		]),
		"ui_warning": _spec(0.22, [
			_hit(0.0, 470.0, 0.16, "wood"),
			_hit(0.088, 470.0, 0.12, "wood"),
		]),
		"ui_error": _spec(0.19, [
			_hit(0.0, 510.0, 0.17, "tile"),
			_hit(0.074, 420.0, 0.16, "tile"),
		]),
		"ui_panel_open": _spec(0.16, [
			_hit(0.0, 1200.0, 0.12, "paper"),
			_hit(0.038, 760.0, 0.08, "wood"),
		]),
		"session_start": _spec(0.48, [
			_hit(0.0, 520.0, 0.07, "chime"),
			_hit(0.12, 660.0, 0.08, "chime"),
			_hit(0.24, 860.0, 0.09, "chime"),
		]),
		"save_stamp": _spec(0.22, [
			_hit(0.0, 330.0, 0.20, "thud"),
			_hit(0.02, 1300.0, 0.10, "paper"),
			_hit(0.092, 740.0, 0.07, "chime"),
		]),
		"camera_lock": _spec(0.13, [
			_hit(0.0, 620.0, 0.14, "wood"),
			_hit(0.038, 860.0, 0.07, "chime"),
		]),
		"camera_zoom": _spec(0.07, [_hit(0.0, 940.0, 0.11, "wood")]),
		"weather_change": _spec(0.42, [
			_hit(0.0, 1150.0, 0.15, "paper"),
			_hit(0.08, 720.0, 0.05, "chime"),
			_hit(0.18, 920.0, 0.055, "chime"),
		]),
		"dialogue_open": _spec(0.18, [
			_hit(0.0, 980.0, 0.11, "paper"),
			_hit(0.035, 780.0, 0.08, "bubble"),
		]),
		"message_send": _spec(0.17, [
			_hit(0.0, 1150.0, 0.13, "paper"),
			_hit(0.045, 900.0, 0.08, "bubble"),
		]),
		"message_reply": _spec(0.22, [
			_hit(0.0, 720.0, 0.07, "bubble"),
			_hit(0.072, 940.0, 0.085, "bubble"),
		]),
		"photo_attach": _spec(0.18, [
			_hit(0.0, 360.0, 0.14, "thud"),
			_hit(0.035, 1350.0, 0.10, "paper"),
		]),
		"bulletin_stamp": _spec(0.28, [
			_hit(0.0, 285.0, 0.23, "thud"),
			_hit(0.02, 1150.0, 0.13, "paper"),
			_hit(0.12, 720.0, 0.06, "chime"),
		]),
		"town_bell": _spec(2.8, [
			_hit(0.0, 392.0, 0.32, "bell"),
			_hit(0.82, 392.0, 0.28, "bell"),
			_hit(1.64, 392.0, 0.24, "bell"),
		]),
		"event_notice": _spec(0.34, [
			_hit(0.0, 640.0, 0.07, "chime"),
			_hit(0.095, 820.0, 0.085, "chime"),
			_hit(0.19, 1010.0, 0.09, "chime"),
		]),
		"door_enter": _spec(0.34, [
			_hit(0.0, 250.0, 0.19, "wood"),
			_hit(0.07, 1450.0, 0.10, "paper"),
			_hit(0.18, 210.0, 0.13, "thud"),
		]),
		"door_exit": _spec(0.34, [
			_hit(0.0, 230.0, 0.18, "wood"),
			_hit(0.08, 1250.0, 0.10, "paper"),
			_hit(0.19, 250.0, 0.12, "thud"),
		]),
		"prop_interact": _spec(0.16, [
			_hit(0.0, 600.0, 0.13, "wood"),
			_hit(0.045, 920.0, 0.06, "tile"),
		]),
		"wardrobe_equip": _spec(0.3, [
			_hit(0.0, 1050.0, 0.15, "cloth"),
			_hit(0.08, 680.0, 0.06, "chime"),
			_hit(0.16, 880.0, 0.075, "chime"),
		]),
		"wardrobe_shuffle": _spec(0.24, [
			_hit(0.0, 1200.0, 0.13, "cloth"),
			_hit(0.045, 1450.0, 0.12, "cloth"),
			_hit(0.092, 1700.0, 0.10, "cloth"),
		]),
		"connection_check": _spec(0.23, [
			_hit(0.0, 680.0, 0.11, "wood"),
			_hit(0.075, 900.0, 0.075, "bubble"),
		]),
		"footstep_outdoor_1": _spec(0.13, [
			_hit(0.0, 0.0, 0.22, "dirt_step"),
			_hit(0.026, 0.0, 0.08, "grit"),
		]),
		"footstep_outdoor_2": _spec(0.14, [
			_hit(0.0, 0.0, 0.20, "dirt_step"),
			_hit(0.014, 0.0, 0.10, "grit"),
			_hit(0.052, 0.0, 0.05, "grit"),
		]),
		"footstep_outdoor_3": _spec(0.12, [
			_hit(0.0, 0.0, 0.23, "dirt_step"),
			_hit(0.034, 0.0, 0.07, "grit"),
		]),
		"footstep_wet_1": _spec(0.17, [
			_hit(0.0, 0.0, 0.20, "wet_step"),
			_hit(0.019, 0.0, 0.13, "splash"),
		]),
		"footstep_wet_2": _spec(0.19, [
			_hit(0.0, 0.0, 0.18, "wet_step"),
			_hit(0.012, 0.0, 0.15, "splash"),
			_hit(0.058, 0.0, 0.06, "splash"),
		]),
		"footstep_wet_3": _spec(0.16, [
			_hit(0.0, 0.0, 0.21, "wet_step"),
			_hit(0.03, 0.0, 0.11, "splash"),
		]),
		"footstep_indoor_1": _spec(0.12, [_hit(0.0, 0.0, 0.20, "floor_step")]),
		"footstep_indoor_2": _spec(0.13, [
			_hit(0.0, 0.0, 0.18, "floor_step"),
			_hit(0.028, 0.0, 0.055, "floor_creak"),
		]),
		"footstep_indoor_3": _spec(0.11, [_hit(0.0, 0.0, 0.21, "floor_step")]),
	}


static func _spec(duration: float, hits: Array) -> Dictionary:
	return {"duration": duration, "hits": hits}


static func _hit(at: float, frequency: float, level: float, kind: String) -> Dictionary:
	return {
		"at": at,
		"frequency": frequency,
		"level": level,
		"kind": kind,
	}


static func _make_cue(
	cue_id: String,
	duration: float,
	hits: Array,
	mix_rate: int,
) -> AudioStreamWAV:
	var sample_count := maxi(1, int(duration * float(mix_rate)))
	var data := PackedByteArray()
	data.resize(sample_count * 2)
	var sound_rng := RandomNumberGenerator.new()
	sound_rng.seed = hash(cue_id) & 0x7fffffff
	var smoothed_noise := 0.0
	for index in sample_count:
		var time := float(index) / float(mix_rate)
		var raw_noise := sound_rng.randf_range(-1.0, 1.0)
		smoothed_noise = lerpf(smoothed_noise, raw_noise, 0.12)
		var bright_noise := raw_noise - smoothed_noise
		var sample := 0.0
		for hit_value: Variant in hits:
			var hit := hit_value as Dictionary
			sample += _sample_hit(
				String(hit.get("kind", "tile")),
				time - float(hit.get("at", 0.0)),
				float(hit.get("frequency", 700.0)),
				float(hit.get("level", 0.1)),
				bright_noise,
				smoothed_noise,
			)
		data.encode_s16(index * 2, int(clampf(sample, -0.92, 0.92) * 32767.0))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = mix_rate
	stream.stereo = false
	stream.data = data
	return stream


static func _sample_hit(
	kind: String,
	time: float,
	frequency: float,
	level: float,
	noise: float,
	body_noise: float,
) -> float:
	if time < 0.0:
		return 0.0
	match kind:
		"bell":
			var bell_attack := minf(time * 70.0, 1.0)
			var bell_decay := exp(-time * 2.2)
			return (
				sin(TAU * frequency * time)
				+ 0.62 * sin(TAU * frequency * 2.01 * time + 0.18)
				+ 0.31 * sin(TAU * frequency * 2.72 * time + 0.44)
				+ 0.17 * sin(TAU * frequency * 4.08 * time + 0.71)
			) * bell_attack * bell_decay * level
		"chime", "bubble":
			var attack := minf(time * 90.0, 1.0)
			var decay := exp(-time * (12.0 if kind == "chime" else 20.0))
			return (
				sin(TAU * frequency * time)
				+ 0.24 * sin(TAU * frequency * 2.01 * time + 0.2)
				+ 0.08 * sin(TAU * frequency * 3.98 * time + 0.5)
			) * attack * decay * level
		"paper":
			return noise * exp(-time * 24.0) * level
		"cloth":
			return noise * sin(minf(time * 28.0, PI)) * exp(-time * 12.0) * level
		"thud":
			return (
				sin(TAU * frequency * time) * exp(-time * 28.0)
				+ noise * exp(-time * 75.0) * 0.28
			) * level
		"dirt_step":
			var contact := exp(-time * 42.0)
			var sole_roll := clampf(1.0 - time / 0.055, 0.0, 1.0)
			return (
				body_noise * contact * 1.4
				+ noise * contact * 0.62
				+ (noise * noise - 0.24) * sole_roll * 0.32
			) * level
		"grit":
			var grain_gate := pow(absf(sin(TAU * 37.0 * time + 0.7)), 9.0)
			return noise * grain_gate * exp(-time * 26.0) * level
		"wet_step":
			var wet_contact := exp(-time * 31.0)
			return (
				body_noise * wet_contact * 1.12
				+ noise * wet_contact * 0.72
				+ absf(body_noise) * exp(-time * 18.0) * 0.38
			) * level
		"splash":
			var droplets := 0.5 + 0.5 * pow(absf(sin(TAU * 43.0 * time + 0.3)), 5.0)
			return (
				noise * droplets * exp(-time * 18.0)
				+ body_noise * exp(-time * 24.0) * 0.55
			) * level
		"floor_step":
			var floor_contact := exp(-time * 52.0)
			var floor_tail := exp(-time * 24.0)
			return (
				body_noise * floor_contact * 1.55
				+ noise * floor_contact * 0.58
				+ (body_noise - noise * 0.16) * floor_tail * 0.32
			) * level
		"floor_creak":
			var creak_shape := sin(minf(time * 27.0, PI)) * exp(-time * 18.0)
			return (body_noise * 1.2 + noise * 0.18) * creak_shape * level
		"wood":
			return (
				sin(TAU * frequency * time) * exp(-time * 58.0)
				+ 0.36 * sin(TAU * frequency * 0.42 * time + 0.2) * exp(-time * 38.0)
				+ noise * exp(-time * 120.0) * 0.38
			) * level
		_:
			return (
				(
					sin(TAU * frequency * time)
					+ 0.46 * sin(TAU * frequency * 2.37 * time + 0.42)
					+ 0.19 * sin(TAU * frequency * 3.91 * time + 0.88)
				) * exp(-time * 88.0) * 0.55
				+ sin(TAU * frequency * 0.29 * time + 0.18) * exp(-time * 52.0) * 0.30
				+ noise * exp(-time * 165.0) * 0.82
			) * level


static func _make_ambience(kind: String) -> AudioStreamWAV:
	var sample_count := int(AMBIENCE_SECONDS * float(AMBIENCE_MIX_RATE))
	var data := PackedByteArray()
	data.resize(sample_count * 2)
	for index in sample_count:
		var time := float(index) / float(AMBIENCE_MIX_RATE)
		var sample := _ambience_sample(kind, time)
		data.encode_s16(index * 2, int(clampf(sample, -0.8, 0.8) * 32767.0))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = AMBIENCE_MIX_RATE
	stream.stereo = false
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_begin = 0
	stream.loop_end = sample_count
	stream.data = data
	return stream


static func _ambience_sample(kind: String, time: float) -> float:
	var air := (
		sin(TAU * time / AMBIENCE_SECONDS)
		+ 0.45 * sin(TAU * 3.0 * time / AMBIENCE_SECONDS + 0.8)
	) * 0.012
	match kind:
		"night":
			var cricket_gate := pow(maxf(0.0, sin(TAU * 5.0 * time / AMBIENCE_SECONDS)), 12.0)
			var cricket := sin(TAU * 2940.0 * time) * cricket_gate * 0.009
			return air * 0.65 + cricket
		"indoor":
			var room_tone := sin(TAU * 55.0 * time) * 0.004
			var fire_gate := pow(maxf(0.0, sin(TAU * 7.0 * time / AMBIENCE_SECONDS + 0.6)), 22.0)
			var fire := sin(TAU * 820.0 * time) * fire_gate * 0.006
			return room_tone + air * 0.28 + fire
		_:
			var bird_a := _periodic_chirp(time, 1.25, 0.12, 1480.0)
			var bird_b := _periodic_chirp(time, 4.65, 0.1, 1760.0)
			return air + (bird_a + bird_b) * 0.012


static func _periodic_chirp(
	time: float,
	start_time: float,
	duration: float,
	frequency: float,
) -> float:
	var local_time := fposmod(time - start_time, AMBIENCE_SECONDS)
	if local_time >= duration:
		return 0.0
	var envelope := sin(PI * local_time / duration)
	return sin(TAU * (frequency + 950.0 * local_time) * local_time) * envelope
