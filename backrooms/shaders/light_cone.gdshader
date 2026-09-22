shader_type spatial;
render_mode unshaded, cull_disabled;
// Fake volumetric cone under a fixture. Alpha fades toward the floor; the
// bottom cap reads as a light pool. Flicker variant uses the same world-hash
// telegraph + dropout logic as the panels (see light_panel.gdshader).

uniform vec4 tint : source_color = vec4(1.0, 0.9, 0.65, 1.0);
uniform float strength : hint_range(0.0, 0.5) = 0.07;
uniform float cone_height = 2.4;
uniform float global_dim = 1.0;
uniform float flicker_enabled = 0.0;

varying vec3 world_pos;
varying float local_y;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	local_y = VERTEX.y;
}

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

void fragment() {
	vec2 key = floor(world_pos.xz / 3.0);
	float phase = hash12(key) * 100.0;
	float e = 1.0;
	if (flicker_enabled > 0.5) {
		float n = sin(TIME * 13.0 + phase) * sin(TIME * 7.3 + phase * 1.7);
		if (n > 0.72) {
			e *= 0.12;
		} else if (n > 0.55) {
			e *= 0.55;
		}
		float drop = hash12(key + floor(TIME * 0.35));
		if (drop < 0.16) {
			e *= 0.05;
		}
		// Slow random kill gate: sometimes fully dark for seconds, then snaps on.
		float gate = hash12(key * 1.7 + floor(TIME * 0.25));
		if (gate < 0.08) {
			e = 0.0;
		}
	}
	float h = clamp(local_y / cone_height + 0.5, 0.0, 1.0);
	float a = h * h * strength * e * global_dim;
	ALBEDO = tint.rgb;
	ALPHA = a;
}
