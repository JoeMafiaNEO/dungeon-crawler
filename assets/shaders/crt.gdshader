shader_type canvas_item;

// CRT filter: scanlines, curvature, vignette, subtle chromatic aberration.
// Samples the screen texture (what's rendered below this layer).

uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_linear_mipmap;

uniform float scanline_strength : hint_range(0.0, 1.0) = 0.25;
uniform float curvature : hint_range(0.0, 1.0) = 0.15;
uniform float vignette_strength : hint_range(0.0, 1.0) = 0.35;
uniform float aberration : hint_range(0.0, 1.0) = 0.5;

vec2 curve_uv(vec2 uv) {
	// Barrel distortion for CRT curvature.
	vec2 cc = uv - 0.5;
	float r2 = dot(cc, cc);
	return uv + cc * r2 * curvature * 2.0;
}

void fragment() {
	vec2 uv = curve_uv(SCREEN_UV);

	// Outside the curved screen: black.
	if (uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0) {
		COLOR = vec4(0.0, 0.0, 0.0, 1.0);
		return;
	}

	// Chromatic aberration: sample RGB slightly offset.
	float ab = aberration * 0.0015;
	vec4 col;
	col.r = texture(screen_texture, uv + vec2(ab, 0.0)).r;
	col.g = texture(screen_texture, uv).g;
	col.b = texture(screen_texture, uv - vec2(ab, 0.0)).b;
	col.a = 1.0;

	// Scanlines.
	float scan = sin(uv.y * 800.0 * 3.14159) * 0.5 + 0.5;
	col.rgb *= 1.0 - scanline_strength * scan;

	// Vignette.
	vec2 vc = uv - 0.5;
	float vig = 1.0 - dot(vc, vc) * vignette_strength * 2.0;
	col.rgb *= clamp(vig, 0.0, 1.0);

	COLOR = col;
}
