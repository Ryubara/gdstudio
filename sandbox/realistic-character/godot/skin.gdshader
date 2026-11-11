// Skin of the realistic character experiment (kit docs: tools/blender/realistic-characters.md#godot).
// The baked maps, a tiling pore normal laid over them up close, dry roughness, a faint oil film on the forehead,
// nose, chin and lips only, and a soft rim where peach fuzz catches light. Subsurface scattering and transmittance
// are Forward+ only; Compatibility draws the same maps without them.
shader_type spatial;
render_mode sss_mode_skin;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap_anisotropic;
uniform sampler2D orm_tex : hint_default_white, filter_linear_mipmap_anisotropic;   // R occlusion, G roughness
uniform sampler2D mask_tex : hint_default_black, filter_linear_mipmap;             // R subsurface, G oil film, B fuzz
uniform sampler2D detail_tex : hint_normal, repeat_enable, filter_linear_mipmap_anisotropic;
uniform float detail_tiles = 24.0;       // repeats of the pore tile across the set's UV square (a tile is about 2 cm)
uniform float detail_strength = 0.55;
uniform float specular = 0.35;           // skin reflects 2.8 % head on; Godot's 0.5 is 4 %
uniform float roughness_scale = 1.0;
uniform float subsurface = 0.18;
uniform float film = 0.18;               // clearcoat where the mask's green says the skin is oily
uniform float film_roughness = 0.35;
uniform float fuzz = 0.22;               // rim where the mask's blue says fine hair grows
uniform float matt = 0.0;                // 1 switches every highlight off, for the shine measurement

void fragment() {
	vec3 orm = texture(orm_tex, UV).rgb;
	vec3 mask = texture(mask_tex, UV).rgb;
	ALBEDO = texture(albedo_tex, UV).rgb;
	AO = orm.r;
	ROUGHNESS = clamp(orm.g * roughness_scale, 0.0, 1.0);
	SPECULAR = specular * (1.0 - matt);
	vec2 n = texture(normal_tex, UV).xy * 2.0 - 1.0;
	vec2 d = texture(detail_tex, UV * detail_tiles).xy * 2.0 - 1.0;
	NORMAL_MAP = vec3((n + d * detail_strength) * 0.5 + 0.5, 0.0);
	SSS_STRENGTH = mask.r * subsurface;
	SSS_TRANSMITTANCE_COLOR = vec4(0.9, 0.22, 0.12, 1.0);
	SSS_TRANSMITTANCE_DEPTH = 0.04;
	SSS_TRANSMITTANCE_BOOST = 0.15;
	CLEARCOAT = mask.g * film * (1.0 - matt);
	CLEARCOAT_ROUGHNESS = film_roughness;
	RIM = mask.b * fuzz * (1.0 - matt);
	RIM_TINT = 0.5;
}
