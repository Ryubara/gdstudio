shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;
// A bullet mark on a surface: a quad whose +Z is the surface normal. Drawn by the shader (a dark
// hole inside a rough scorched ring), or from `mark_texture` when `use_texture` is on, so a game
// restyles it by changing a colour or by dropping in a picture. Works in every renderer (a
// `Decal` node does not draw in Compatibility, which the web build uses).

// The marks fade through the instance uniform `fade` (1 = whole, 0 = gone), which `Impacts`
// sets on each mark. A material of your own fades the same way when it declares it.
instance uniform float fade : hint_range(0.0, 1.0) = 1.0;

group_uniforms look;
// The colour of the hole's centre.
uniform vec4 hole_color : source_color = vec4(0.03, 0.03, 0.035, 1.0);
// The colour of the ring around the hole.
uniform vec4 ring_color : source_color = vec4(0.12, 0.115, 0.11, 1.0);
// How strong the ring is (0 draws the hole alone).
uniform float ring_strength : hint_range(0.0, 1.0) = 0.55;
// How big the hole is, as a share of the quad.
uniform float hole_size : hint_range(0.05, 0.6) = 0.2;
// How rough the ring's edge is: 0 is a clean circle, 1 has sharp chips.
uniform float roughness : hint_range(0.0, 1.0) = 0.6;

group_uniforms picture;
// Draw `mark_texture` (its colour times `texture_tint`, its alpha as the shape) instead of the hole.
uniform bool use_texture = false;
uniform sampler2D mark_texture : source_color, filter_linear_mipmap, repeat_disable;
uniform vec4 texture_tint : source_color = vec4(1.0);

group_uniforms depth;
// A mark lies on the surface lifted by this much, so the surface does not cut through it ...
uniform float lift : hint_range(0.0, 0.1) = 0.004;
// ... plus this much for every metre between it and the camera: a fixed lift flickers far away.
uniform float lift_per_metre : hint_range(0.0, 0.02) = 0.002;

void vertex() {
	vec3 world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float distance_to_camera = length(world - CAMERA_POSITION_WORLD);
	// The node's z scale stays 1, so this is in metres.
	VERTEX.z += lift + lift_per_metre * distance_to_camera;
}

void fragment() {
	vec2 p = UV - vec2(0.5);
	vec3 colour;
	float alpha;
	if (use_texture) {
		vec4 picture = texture(mark_texture, UV);
		colour = picture.rgb * texture_tint.rgb;
		alpha = picture.a * texture_tint.a;
	} else {
		float r = length(p) * 2.0;
		float a = atan(p.y, p.x);
		float chips = pow(abs(sin(a * 3.0 + sin(a * 7.0) * 0.9)), 6.0);
		float reach = mix(0.7, 0.45 + 0.4 * chips, roughness);
		float hole = 1.0 - smoothstep(hole_size * 0.8, hole_size, r);
		float ring = (1.0 - smoothstep(reach * 0.45, reach, r)) * ring_strength;
		colour = mix(ring_color.rgb, hole_color.rgb, hole);
		alpha = max(hole, ring) * mix(ring_color.a, hole_color.a, hole);
	}
	ALBEDO = colour;
	ALPHA = alpha * fade;
}
