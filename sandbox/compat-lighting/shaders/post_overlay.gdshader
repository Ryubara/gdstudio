// Vignette + grain drawn as a translucent overlay: no screen-texture read, so no back-buffer copy.
// It cannot grade colour (no access to what is behind it), only darken and add noise.
shader_type canvas_item;

uniform float vignette_strength = 0.55;
uniform float grain_amount = 0.05;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

void fragment() {
	vec2 centered = UV - 0.5;
	float vig = vignette_strength * smoothstep(0.25, 0.85, length(centered * vec2(1.3, 1.0)));
	float grain = (hash(UV * 1000.0 + fract(TIME)) - 0.5) * grain_amount;
	COLOR = vec4(vec3(0.0) + max(grain, 0.0) * 4.0, clamp(vig + abs(grain), 0.0, 1.0));
}
