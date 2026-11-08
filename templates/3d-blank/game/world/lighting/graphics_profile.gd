class_name GraphicsProfile
extends Node
## Turns on what only the Forward+ renderer can draw. The level is lit to look good on the
## Compatibility renderer first (baked bounce light, one real-time sun, a procedural sky): the web
## build and phones run that. On a desktop, where the project runs Forward+, this node adds
## screen-space ambient occlusion and indirect light, reflections, volumetric fog, dynamic global
## illumination (SDFGI) and finer shadows on top, from the same scene. On Compatibility it does
## nothing at all, so one level serves both.
##
## Put one in a level, point it at the level's `WorldEnvironment`, sun and `LightmapGI`, and tick
## what you want.

enum GlobalLight {
	BAKED,  ## Bounce light comes from the level's baked lightmaps, as on the web.
	SDFGI,  ## Bounce light is computed live from the whole scene and the lightmaps are hidden.
}

## The renderer this build runs; Forward+ is the only one that has the extras.
const FORWARD_PLUS := "forward_plus"

@export_group("Targets")
## The environment to add the extras to. The shared resource is copied, never edited.
@export var world_environment: WorldEnvironment
## The sun whose shadows get finer.
@export var sun: DirectionalLight3D
## The baked lightmaps, hidden when `global_light` is SDFGI.
@export var lightmap: LightmapGI

@export_group("Forward+ extras")
## Turns every extra below on or off together.
@export var enabled := true
## Where bounce light comes from.
@export var global_light: GlobalLight = GlobalLight.BAKED
## Darkens creases and contact points (SSAO).
@export var ambient_occlusion := true
## Colour bleeding from lit surfaces onto their neighbours in screen space (SSIL).
@export var indirect_light := true
## Reflections of the scene on glossy surfaces (SSR).
@export var reflections := true
## Light shafts and a thick haze that the sun and the shadows shape.
@export var volumetric_fog := true
## How thick the volumetric haze is.
@export_range(0.0, 0.1, 0.001) var volumetric_density := 0.012
## Brightness: the same scene reads darker in Forward+ than in Compatibility, so this lifts the
## tonemap exposure to match what the web build shows. Set 1 to take the plain tonemap.
@export_range(0.5, 2.0, 0.05) var exposure_match := 1.35
## Four shadow cascades, a sharper atlas and softer edges for the sun.
@export var finer_shadows := true

## The level's own environment, kept so that applying twice never stacks the extras.
var _source: Environment


## True when this build can draw the extras.
static func is_supported() -> bool:
	return RenderingServer.get_current_rendering_method() == FORWARD_PLUS


func _ready() -> void:
	if enabled and is_supported():
		apply()


## Switches the extras on (Forward+ only; does nothing otherwise).
func apply() -> void:
	if not is_supported():
		return
	if world_environment != null and world_environment.environment != null:
		if _source == null:
			_source = world_environment.environment
		var environment := _source.duplicate() as Environment
		environment.ssao_enabled = ambient_occlusion
		environment.ssil_enabled = indirect_light
		environment.ssr_enabled = reflections
		environment.sdfgi_enabled = global_light == GlobalLight.SDFGI
		environment.volumetric_fog_enabled = volumetric_fog
		environment.volumetric_fog_density = volumetric_density
		environment.volumetric_fog_sky_affect = 0.0
		environment.tonemap_exposure *= exposure_match
		world_environment.environment = environment
	if lightmap != null:
		lightmap.visible = global_light == GlobalLight.BAKED
	if finer_shadows:
		_finer_shadows()


func _finer_shadows() -> void:
	RenderingServer.directional_shadow_atlas_set_size(4096, true)
	RenderingServer.directional_soft_shadow_filter_set_quality(
		RenderingServer.SHADOW_QUALITY_SOFT_HIGH
	)
	if sun != null:
		sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
		sun.directional_shadow_max_distance = 120.0
