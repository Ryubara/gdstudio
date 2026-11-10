shader_type canvas_item;
render_mode blend_premul_alpha;
// The minimap's picture, its background and its border in one pass. The picture is a snapshot
// (the live camera's render target, or a baked image) taken with its middle at `source_centre`
// metres on the map plane, turned by `source_turn`, covering `source_half` metres either side;
// this shader shows the part of it that the widget looks at now (`view_*`), so the picture moves
// smoothly between snapshots. Widget coordinates `p` run from -1 to 1, y down.

group_uniforms look;
uniform bool circular = true;
uniform float corner_ratio : hint_range(0.0, 1.0) = 0.25;
uniform vec4 background_color : source_color = vec4(0.04, 0.06, 0.09, 0.85);
uniform vec4 border_color : source_color = vec4(0.9, 0.93, 1.0, 0.9);
uniform float border_px = 3.0;
uniform float widget_px = 220.0;
uniform float edge_fade : hint_range(0.0, 1.0) = 0.12;
uniform float opacity : hint_range(0.0, 1.0) = 1.0;
uniform bool tint_enabled = true;
uniform vec4 tint_dark : source_color = vec4(0.1, 0.14, 0.2, 1.0);
uniform vec4 tint_light : source_color = vec4(0.62, 0.76, 0.85, 1.0);
group_uniforms;

group_uniforms view;
uniform vec2 view_centre = vec2(0.0);
uniform float view_turn = 0.0;
uniform float view_range = 30.0;
group_uniforms;

group_uniforms source;
uniform sampler2D map_texture : source_color, filter_linear, repeat_disable;
uniform bool has_map = false;
uniform vec2 source_centre = vec2(0.0);
uniform float source_turn = 0.0;
uniform vec2 source_half = vec2(30.0);
group_uniforms;

vec2 rotate2(vec2 v, float a) {
	float c = cos(a);
	float s = sin(a);
	return vec2(v.x * c - v.y * s, v.x * s + v.y * c);
}

// Distance inside the widget's shape, in widget units: positive inside, zero on the border.
float depth_inside(vec2 p) {
	if (circular) {
		return 1.0 - length(p);
	}
	float r = corner_ratio;
	vec2 q = abs(p) - vec2(1.0 - r);
	return -(length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r);
}

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float depth = depth_inside(p);
	float aa = fwidth(depth);
	float inside = clamp(depth / max(aa, 0.0001), 0.0, 1.0);

	vec4 result = vec4(background_color.rgb, background_color.a);
	if (has_map) {
		vec2 world = view_centre + rotate2(p * view_range, -view_turn);
		vec2 local = rotate2(world - source_centre, source_turn);
		vec2 uv = 0.5 + local / (2.0 * source_half);
		vec4 c = texture(map_texture, uv);
		float within = step(0.0, uv.x) * step(uv.x, 1.0) * step(0.0, uv.y) * step(uv.y, 1.0);
		if (tint_enabled) {
			float lum = dot(c.rgb, vec3(0.299, 0.587, 0.114));
			c.rgb = mix(tint_dark.rgb, tint_light.rgb, clamp(lum, 0.0, 1.0));
		}
		float fade = edge_fade <= 0.0 ? 1.0 : clamp(depth / edge_fade, 0.0, 1.0);
		float a = c.a * within * fade;
		result.rgb = mix(result.rgb, c.rgb, a);
		result.a = max(result.a, a);
	}
	float border = (border_px * 2.0 / widget_px);
	if (border > 0.0) {
		float on_border = clamp((border - depth) / max(aa, 0.0001), 0.0, 1.0);
		result.rgb = mix(result.rgb, border_color.rgb, on_border * border_color.a);
		result.a = max(result.a, on_border * border_color.a);
	}
	result.a *= inside * opacity;
	COLOR = vec4(result.rgb * result.a, result.a);
}
