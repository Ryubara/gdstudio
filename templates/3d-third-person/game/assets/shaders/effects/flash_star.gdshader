shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled;
// A toon flash: a spiked star in two flat colours on a camera-facing quad (a muzzle flash, a
// spark of light). Put it on a `QuadMesh` that a one-shot `CPUParticles3D` draws: the particle's
// colour alpha fades it, its scale sizes it and its angle rolls it. It adds light to what is
// behind it, so it never darkens, and works in every renderer, the Compatibility one included.

group_uniforms look;
// The colour of the star's middle.
uniform vec4 core_color : source_color = vec4(1.0, 0.97, 0.82, 1.0);
// The colour of its spikes.
uniform vec4 spike_color : source_color = vec4(1.0, 0.58, 0.16, 1.0);
// How many spikes the star has.
uniform float spikes : hint_range(2.0, 12.0, 1.0) = 5.0;
// How deep the gaps between the spikes cut: 0 is a disc, 1 a thin star.
uniform float spike_depth : hint_range(0.0, 1.0) = 0.6;
// How big the middle is, as a share of the quad.
uniform float core_size : hint_range(0.05, 0.6) = 0.4;

varying float roll;

void vertex() {
	// Face the camera and keep the node's (and the particle's) scale.
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(
		INV_VIEW_MATRIX[0] * length(MODEL_MATRIX[0].xyz),
		INV_VIEW_MATRIX[1] * length(MODEL_MATRIX[1].xyz),
		INV_VIEW_MATRIX[2] * length(MODEL_MATRIX[2].xyz),
		MODEL_MATRIX[3]);
	// A CPU particle's angle arrives as custom data x.
	roll = INSTANCE_CUSTOM.x;
}

void fragment() {
	vec2 p = (UV - vec2(0.5)) * 2.0;
	float c = cos(roll);
	float s = sin(roll);
	p = vec2(c * p.x - s * p.y, s * p.x + c * p.y);
	float r = length(p);
	float a = atan(p.y, p.x);
	float star = pow(abs(cos(a * spikes * 0.5)), 3.0);
	float edge = mix(1.0, 0.18 + 0.82 * star, spike_depth);
	float soft = fwidth(r) * 1.5;
	float shape = 1.0 - smoothstep(edge - soft, edge, r);
	float core = 1.0 - smoothstep(core_size * edge - soft, core_size * edge, r);
	ALBEDO = mix(spike_color.rgb, core_color.rgb, core);
	ALPHA = shape * COLOR.a;
}
