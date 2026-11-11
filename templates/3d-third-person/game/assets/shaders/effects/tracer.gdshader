shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, skip_vertex_transform;
// A tracer: a thin glowing streak drawn by one instance of a `MultiMesh` of `QuadMesh`es (the
// `TracerPool`). The instance's Y axis runs from the streak's tail to its head, centred on the
// instance's origin, and its X axis is as long as the streak is wide; the quad turns about the Y
// axis to face the camera here. The instance colour tints it, its alpha fades it, and the custom
// data's x is its brightness (colours may be stored in 8 bits). Additive and
// unshaded, so it never darkens and needs no light: it works in every renderer, the Compatibility
// one included.

// How hard the streak's edges fall off across its width: higher is a harder core.
uniform float edge_softness : hint_range(0.5, 8.0) = 2.0;
// How bright the tail is against the head, along the streak.
uniform float tail_share : hint_range(0.0, 1.0) = 0.15;

varying float along;
varying float energy;

void vertex() {
	vec3 middle = MODEL_MATRIX[3].xyz;
	vec3 axis = MODEL_MATRIX[1].xyz;
	float half_width = length(MODEL_MATRIX[0].xyz) * 0.5;
	vec3 world = middle + axis * VERTEX.y;
	vec3 to_camera = INV_VIEW_MATRIX[3].xyz - world;
	vec3 side = cross(axis, to_camera);
	float side_length = length(side);
	side = side_length > 0.00001 ? side / side_length : normalize(MODEL_MATRIX[0].xyz);
	world += side * (VERTEX.x * 2.0) * half_width;
	VERTEX = (VIEW_MATRIX * vec4(world, 1.0)).xyz;
	NORMAL = (VIEW_MATRIX * vec4(normalize(to_camera), 0.0)).xyz;
	along = clamp(UV.y, 0.0, 1.0);
	energy = INSTANCE_CUSTOM.x;
}

void fragment() {
	float across = abs(UV.x * 2.0 - 1.0);
	float core = pow(clamp(1.0 - across, 0.0, 1.0), edge_softness);
	// UV.y is 0 at the head (the quad's +Y) and 1 at the tail.
	float run = mix(1.0, tail_share, along);
	ALBEDO = COLOR.rgb * energy;
	ALPHA = clamp(COLOR.a * core * run, 0.0, 1.0);
}
