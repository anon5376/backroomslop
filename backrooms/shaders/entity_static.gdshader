shader_type spatial;
render_mode cull_disabled;
// Near-black wire body with crawling analog static in emission.

uniform vec4 base_color : source_color = vec4(0.015, 0.015, 0.02, 1.0);
uniform float static_amount : hint_range(0.0, 1.0) = 0.4;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void fragment() {
	ALBEDO = base_color.rgb;
	ROUGHNESS = 0.9;
	SPECULAR = 0.2;
	float g = hash(UV * 40.0 + floor(TIME * 10.0));
	float spark = step(1.0 - static_amount * 0.22, g);
	EMISSION = vec3(0.45, 0.47, 0.5) * spark * static_amount;
	// Cold rim: silhouette stays readable in dead-fixture darkness.
	float rim = pow(1.0 - clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0), 2.5);
	EMISSION += vec3(0.10, 0.13, 0.16) * rim;
}
