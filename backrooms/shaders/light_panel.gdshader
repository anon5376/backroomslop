shader_type spatial;
render_mode unshaded, cull_disabled;
// Fluorescent troffer panel. Phase/warmth derive from world position, so every
// fixture is stable and unique with no per-instance data. flicker_enabled (0/1)
// picks steady vs telegraph-noise behavior. Dead panels use a plain dark material.
// The diffuser is drawn in-shader: twin tube strips under a prismatic lens with
// a soft frame falloff, so panels read as fixtures instead of flat white quads.

uniform vec4 steady_color : source_color = vec4(1.0, 0.93, 0.72, 1.0);
uniform float energy : hint_range(0.0, 8.0) = 1.5;
uniform float global_dim = 1.0;
uniform float flicker_enabled = 0.0;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

void fragment() {
	vec2 key = floor(world_pos.xz / 3.0);
	float phase = hash12(key) * 100.0;
	float warmth = 0.9 + 0.2 * hash12(key + 7.0);
	float e = energy;
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
	// Twin tubes across the short axis: bright at 1/4 and 3/4, dark spine + edges.
	float tubes = 0.55 + 0.45 * pow(abs(sin(UV.y * 6.28318)), 0.8);
	// Frame falloff: the lens seats into the troffer housing at the borders.
	float edge = smoothstep(0.0, 0.07, UV.x) * (1.0 - smoothstep(0.93, 1.0, UV.x))
		* smoothstep(0.0, 0.10, UV.y) * (1.0 - smoothstep(0.90, 1.0, UV.y));
	float lens = tubes * mix(0.30, 1.0, edge);
	// Tube end-caps: electrodes darken the last few centimeters.
	float ends = smoothstep(0.0, 0.05, UV.x) * (1.0 - smoothstep(0.95, 1.0, UV.x));
	lens *= mix(0.65, 1.0, ends);
	ALBEDO = steady_color.rgb * vec3(warmth, warmth * 0.99, 1.0 / warmth) * e * global_dim * lens;
}
