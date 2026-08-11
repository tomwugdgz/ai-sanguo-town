shader_type canvas_item;

uniform float grayscale_strength : hint_range(0.0, 1.0) = 1.0;

void fragment() {
	vec4 source = texture(TEXTURE, UV) * COLOR;
	float gray = dot(source.rgb, vec3(0.299, 0.587, 0.114));
	COLOR = vec4(mix(source.rgb, vec3(gray), grayscale_strength), source.a);
}
