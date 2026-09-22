shader_type canvas_item;
// VHS found-footage post-process for a full-screen ColorRect.

uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_linear;
uniform float grain : hint_range(0.0, 1.0) = 0.10;
uniform float tracking : hint_range(0.0, 1.0) = 0.5;
uniform float chroma : hint_range(0.0, 0.02) = 0.003;
uniform float vignette : hint_range(0.0, 1.0) = 0.45;
uniform float burst = 0.0; // full-static takeover 0..1 (death / scares)

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void fragment() {
	vec2 uv = SCREEN_UV;
	// Rolling tracking bar that shoves scanlines sideways.
	float bar_y = fract(TIME * 0.22);
	float bar_d = abs(uv.y - bar_y);
	float bar = smoothstep(0.035, 0.0, bar_d) * tracking;
	uv.x += bar * 0.008 * sin(TIME * 40.0);
	// Chroma shift.
	vec2 off = vec2(chroma, 0.0);
	vec4 c;
	c.r = texture(screen_texture, uv + off).r;
	c.g = texture(screen_texture, uv).g;
	c.b = texture(screen_texture, uv - off).b;
	c.a = 1.0;
	// Scanlines.
	c.rgb *= 0.92 + 0.08 * sin(uv.y * 800.0);
	// Grain (+burst lift).
	float g = hash(uv * vec2(1920.0, 1080.0) + fract(TIME) * 100.0);
	c.rgb += (g - 0.5) * (grain + burst * 0.9);
	// Tracking bar noise.
	c.rgb += bar * (hash(vec2(floor(TIME * 24.0), floor(uv.x * 60.0))) - 0.3) * 0.22;
	// Vignette.
	vec2 d = uv - vec2(0.5);
	c.rgb *= 1.0 - vignette * dot(d, d) * 2.2;
	// Full static takeover.
	if (burst > 0.01) {
		float s = hash(uv * 913.0 + fract(TIME * 7.0) * 500.0);
		c.rgb = mix(c.rgb, vec3(s), burst * 0.85);
	}
	COLOR = c;
}
