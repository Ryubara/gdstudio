// Prototype surface: a world-space grid on any shape, at any size, with no texture file.
//
// The pattern follows the world, not the mesh's UVs, so a 1 m cell is 1 m on a wall, a floor and a ramp whatever the
// node's scale. A box resized in the inspector keeps its grid. Three planes (x, y, z) are blended by the surface
// normal, so a slope has no seam.
//
// Layers, from the bottom: the base colour, a faint checker of whole cells (reads depth on a flat floor), thin lines
// between cells, and a heavier line every few cells. A line fades out when it would be thinner than a pixel,
// so a far floor is a calm tone, not noise. Everything is one pass with no screen read: it costs the same in the
// Compatibility renderer and the web build as a plain material.
shader_type spatial;

group_uniforms surface;
uniform vec4 base_color : source_color = vec4(0.62, 0.64, 0.68, 1.0);
uniform float roughness : hint_range(0.0, 1.0) = 0.92;

// The grid's size comes from the project, not from the material, so the squares equal the step the editor snaps to
// and every surface agrees (Project Settings > Shader Globals).
// Metres per cell: also the 3D editor's translate snap, which the prototype_grid plugin sets.
global uniform float prototype_cell_size;
// A heavier line every this many cells: the 3D editor's viewport grid does the same (8 by default).
global uniform float prototype_major_every;

group_uniforms grid;
// How much darker the lines and the checker are than the base colour (0 hides the layer).
uniform float line_strength : hint_range(0.0, 1.0) = 0.22;
uniform float major_strength : hint_range(0.0, 1.0) = 0.42;
uniform float checker_strength : hint_range(0.0, 0.3) = 0.05;
// Line widths as a fraction of a cell.
uniform float line_width : hint_range(0.0, 0.2) = 0.018;
uniform float major_width : hint_range(0.0, 0.2) = 0.032;

varying vec3 world_position;
varying vec3 world_normal;

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize(mat3(MODEL_MATRIX) * NORMAL);
}

// 1 on a line of width `width` (in cells) around each whole number of `p`, 0 elsewhere; `fade` removes the lines a
// pixel can no longer resolve.
float lines(vec2 p, float width) {
	vec2 footprint = max(fwidth(p), vec2(0.00001));
	vec2 distance_to_line = abs(fract(p - 0.5) - 0.5);
	vec2 coverage = 1.0 - smoothstep(vec2(width) - footprint, vec2(width) + footprint, distance_to_line);
	float fade = 1.0 - smoothstep(0.35, 0.7, max(footprint.x, footprint.y));
	return max(coverage.x, coverage.y) * fade;
}

// The layered pattern on one plane: x = darkening from lines, y = darkening from the checker.
vec2 pattern(vec2 world_plane) {
	vec2 cell = world_plane / prototype_cell_size;
	vec2 major = cell / prototype_major_every;
	float minor_line = lines(cell, line_width);
	float major_line = lines(major, major_width / prototype_major_every);
	float line_dark = max(minor_line * line_strength, major_line * major_strength);
	vec2 id = floor(cell);
	float checker = mod(id.x + id.y, 2.0);
	float checker_fade = 1.0 - smoothstep(0.35, 0.7, max(fwidth(cell.x), fwidth(cell.y)));
	return vec2(line_dark, checker * checker_strength * checker_fade);
}

void fragment() {
	vec3 weights = pow(abs(world_normal), vec3(8.0));
	weights /= weights.x + weights.y + weights.z;
	vec2 on_x = pattern(world_position.zy);
	vec2 on_y = pattern(world_position.xz);
	vec2 on_z = pattern(world_position.xy);
	vec2 mixed = on_x * weights.x + on_y * weights.y + on_z * weights.z;
	float darker = clamp(mixed.x + mixed.y, 0.0, 0.9);
	ALBEDO = base_color.rgb * (1.0 - darker);
	ROUGHNESS = roughness;
	METALLIC = 0.0;
	SPECULAR = 0.12;
}
