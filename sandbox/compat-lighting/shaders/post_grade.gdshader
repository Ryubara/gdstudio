// Full-screen colour grade + vignette + grain. Reads the screen texture, so Compatibility
// has to copy the back buffer first; that copy is the cost this spike measures.
shader_type canvas_item;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform vec3 shadow_tint : source_color = vec3(0.82, 0.92, 1.1);
uniform vec3 highlight_tint : source_color = vec3(1.08, 1.0, 0.9);
uniform float saturation = 0.85;
uniform float vignette_strength = 0.55;
uniform float grain_amount = 0.05;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

void fragment() {
	vec3 col = textureLod(screen_tex, SCREEN_UV, 0.0).rgb;
	float luma = dot(col, vec3(0.299, 0.587, 0.114));
	col = mix(vec3(luma), col, saturation);
	col *= mix(shadow_tint, highlight_tint, smoothstep(0.0, 0.8, luma));
	vec2 centered = SCREEN_UV - 0.5;
	col *= 1.0 - vignette_strength * smoothstep(0.25, 0.85, length(centered * vec2(1.3, 1.0)));
	col += (hash(SCREEN_UV * 1000.0 + fract(TIME)) - 0.5) * grain_amount;
	COLOR = vec4(col, 1.0);
}
