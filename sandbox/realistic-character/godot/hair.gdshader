// Hair cards of the realistic character experiment (kit docs: tools/blender/realistic-characters.md#hair).
// Hair has two highlights (Marschner and others, 2003): a sharp, colourless one off the strand's surface, shifted
// towards the tip, and a broad one in the hair's own colour that went through the strand, shifted towards the root.
// Both are computed here from the strand's direction (the card's V axis), the way Kajiya and Kay and Scheuermann
// did for cards, so they work in Forward+ and in Compatibility alike; StandardMaterial3D has one anisotropic
// highlight, in Forward+ only.
shader_type spatial;
render_mode cull_disabled, depth_prepass_alpha;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic;   // colour, alpha = coverage
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap;
uniform sampler2D orm_tex : hint_default_white, filter_linear_mipmap;            // R depth in the lock, G roughness
uniform float primary = 0.03;
uniform float primary_shift = 0.10;
uniform float primary_power = 110.0;
uniform float secondary = 0.07;
uniform float secondary_shift = -0.12;
uniform float secondary_power = 22.0;
uniform float matt = 0.0;                // 1 switches the highlights off, for the shine measurement

varying vec3 strand;
varying vec3 volume;
varying float jitter;
varying vec3 tint;

void vertex() {
	// A card is drawn from both sides with the same normal: the scalp's or the lock's, which the build stored.
	// (Left to the engine, the side that faces away is lit from inside the head and goes black.)
	volume = normalize((MODELVIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	strand = normalize((MODELVIEW_MATRIX * vec4(BINORMAL, 0.0)).xyz);
}

void fragment() {
	vec4 colour = texture(albedo_tex, UV);
	vec3 orm = texture(orm_tex, UV).rgb;
	ALBEDO = colour.rgb * mix(0.42, 0.62, orm.r);
	ALPHA = colour.a;
	AO = mix(0.8, 1.0, orm.r);
	NORMAL = normalize(volume);
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;     // the built-in highlight is off: light() below draws hair's two
	// Each strand shifts its highlights a little, or they line up into one band across a card.
	jitter = (colour.r + colour.g - 0.25) * 0.5 + (orm.r - 0.8) * 0.25 + (texture(normal_tex, UV).r - 0.5) * 0.2;
	tint = colour.rgb;
}

float lobe(vec3 t, vec3 h, float power) {
	float th = dot(t, h);
	float s = sqrt(max(1.0 - th * th, 0.0));
	return smoothstep(-1.0, 0.0, th) * pow(s, power);
}

void light() {
	float wrap = clamp((dot(NORMAL, LIGHT) + 0.45) / 1.45, 0.0, 1.0);
	vec3 radiance = ATTENUATION * LIGHT_COLOR / PI;
	DIFFUSE_LIGHT += wrap * radiance;
	vec3 h = normalize(VIEW + LIGHT);
	vec3 along = normalize(strand);
	vec3 t1 = normalize(along + NORMAL * (primary_shift + jitter));
	vec3 t2 = normalize(along + NORMAL * (secondary_shift + jitter));
	vec3 glints = primary * lobe(t1, h, primary_power) * vec3(1.0);
	glints += secondary * lobe(t2, h, secondary_power) * tint * 4.0;
	SPECULAR_LIGHT += glints * wrap * radiance * (1.0 - matt) * PI;
}
