// chrono_field.gdshader — Chrono-Weaver temporal dome (Strategist / aetherborn mage).
// Screen-space refraction field: samples the screen texture at a time-animated distortion
// offset and tints teal. Modest alpha keeps overdraw cost low.
// Assigned to a SphereMesh dome (~radius 0.9) centred on the character.
shader_type spatial;
render_mode blend_mix, cull_disabled, unshaded, depth_draw_never;

// Screen texture — sampled at distorted UV for refraction look.
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;

// Teal tint applied on top of the refracted screen colour.
uniform vec4 tint_color : source_color = vec4(0.15, 0.85, 0.90, 1.0);

// Controls how strong the UV wobble is (keep small — ~0.006–0.012 reads well).
uniform float distortion_amount : hint_range(0.0, 0.05) = 0.008;

// Overall dome alpha (transparency of the whole field).
uniform float dome_alpha : hint_range(0.0, 1.0) = 0.30;

// Frequency of the animated wobble.
uniform float wobble_freq : hint_range(0.1, 8.0) = 2.2;

void vertex() {
	// No vertex displacement — let the dome sit as-is.
}

void fragment() {
	// Animated distortion offset — two overlapping sine waves driven by TIME
	// so the wobble feels organic and not perfectly periodic.
	float wave_a = sin(TIME * wobble_freq + FRAGCOORD.y * 0.018) * distortion_amount;
	float wave_b = cos(TIME * wobble_freq * 0.73 + FRAGCOORD.x * 0.022) * distortion_amount * 0.6;

	vec2 distorted_uv = SCREEN_UV + vec2(wave_a + wave_b, wave_b - wave_a * 0.5);

	// Sample refracted background
	vec3 refracted = texture(screen_tex, distorted_uv).rgb;

	// Blend teal tint over the refracted colour
	vec3 tinted = mix(refracted, tint_color.rgb, tint_color.a * 0.55);

	// Fresnel-like rim: stronger alpha at grazing angles (NORMAL.z near 0 in view space)
	float rim_factor = 1.0 - abs(dot(NORMAL, vec3(0.0, 0.0, 1.0)));
	float alpha = dome_alpha * (0.35 + rim_factor * 0.65);

	ALBEDO = tinted;
	ALPHA  = alpha;
}
