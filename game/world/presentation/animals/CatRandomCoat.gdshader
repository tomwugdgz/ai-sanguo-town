shader_type canvas_item;

uniform vec4 front_coat_color : source_color = vec4(0.30, 0.31, 0.34, 1.0);
uniform vec4 back_coat_color : source_color = vec4(0.82, 0.46, 0.17, 1.0);
uniform vec4 patch_coat_color : source_color = vec4(0.72, 0.61, 0.42, 1.0);
uniform float pattern_seed : hint_range(0.0, 1.0) = 0.0;
uniform float direction_mode : hint_range(0.0, 3.0) = 0.0;
uniform vec2 frame_size = vec2(128.0);


float random_value(vec2 coordinate) {
	return fract(
		sin(
			dot(coordinate, vec2(12.9898, 78.233))
			+ pattern_seed * 91.731
		) * 43758.5453
	);
}


void fragment() {
	vec4 sprite_modulate = COLOR;
	vec4 source = texture(TEXTURE, UV);
	float maximum = max(source.r, max(source.g, source.b));
	float minimum = min(source.r, min(source.g, source.b));
	float saturation = maximum > 0.001 ? (maximum - minimum) / maximum : 0.0;
	bool is_orange_fur = (
		source.a > 0.001
		&& saturation >= 0.30
		&& source.r > source.g * 1.10
		&& source.r > source.b * 1.35
	);
	if (is_orange_fur) {
		vec2 pixel_coordinate = UV / TEXTURE_PIXEL_SIZE;
		vec2 local_uv = mod(pixel_coordinate, frame_size) / frame_size;
		float front_coordinate = local_uv.x;
		if (direction_mode > 0.5 && direction_mode < 1.5) {
			front_coordinate = 1.0 - local_uv.x;
		} else if (direction_mode > 1.5 && direction_mode < 2.5) {
			front_coordinate = local_uv.y;
		} else if (direction_mode > 2.5) {
			front_coordinate = 1.0 - local_uv.y;
		}
		float uneven_boundary = (
			0.52
			+ sin(local_uv.y * 18.0 + pattern_seed * 11.0) * 0.055
			+ (random_value(vec2(floor(local_uv.y * 7.0), 2.0)) - 0.5) * 0.08
		);
		vec3 selected_coat = mix(
			back_coat_color.rgb,
			front_coat_color.rgb,
			step(uneven_boundary, front_coordinate)
		);
		vec2 patch_center = vec2(
			0.38 + random_value(vec2(3.0, 7.0)) * 0.24,
			0.36 + random_value(vec2(8.0, 4.0)) * 0.28
		);
		float patch_radius = 0.12 + random_value(vec2(6.0, 9.0)) * 0.07;
		float patch_mask = 1.0 - smoothstep(
			patch_radius,
			patch_radius + 0.035,
			distance(local_uv, patch_center)
		);
		selected_coat = mix(selected_coat, patch_coat_color.rgb, patch_mask);
		float preserved_shading = 0.12 + pow(maximum, 1.05);
		source.rgb = clamp(selected_coat * preserved_shading, 0.0, 1.0);
	}
	COLOR = source * sprite_modulate;
}
