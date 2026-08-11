shader_type canvas_item;

uniform vec4 feather_color : source_color = vec4(0.18, 0.48, 0.78, 1.0);
uniform vec4 belly_color : source_color = vec4(0.96, 0.72, 0.16, 1.0);


void fragment() {
	vec4 sprite_modulate = COLOR;
	vec4 source = texture(TEXTURE, UV);
	float maximum = max(source.r, max(source.g, source.b));
	float minimum = min(source.r, min(source.g, source.b));
	float saturation = maximum > 0.001 ? (maximum - minimum) / maximum : 0.0;
	bool is_blue_feather = (
		source.a > 0.001
		&& saturation > 0.25
		&& source.b > source.r * 1.22
		&& source.b > source.g * 1.08
	);
	bool is_yellow_belly = (
		source.a > 0.001
		&& saturation > 0.28
		&& source.r > source.b * 1.35
		&& source.g > source.b * 1.16
	);
	if (is_blue_feather || is_yellow_belly) {
		vec3 selected = (
			is_blue_feather
			? feather_color.rgb
			: belly_color.rgb
		);
		float preserved_shading = 0.18 + pow(maximum, 1.08);
		source.rgb = clamp(selected * preserved_shading, 0.0, 1.0);
	}
	COLOR = source * sprite_modulate;
}
