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
## what you want. A change in the inspector (or the remote inspector) applies at once while the
## game runs; the editor's own viewport is left alone.

enum GlobalLight {
	BAKED,  ## Bounce light comes from the level's baked lightmaps, as on the web.
	SDFGI,  ## Bounce light is computed live from the whole scene and the lightmaps are hidden.
}

## The renderer this build runs; Forward+ is the only one that has the extras.
const FORWARD_PLUS := "forward_plus"

@export_group("Targets")
## The environment to add the extras to. The shared resource is copied, never edited.
@export var world_environment: WorldEnvironment:
	set(value):
		_restore_environment()
		_source = null
		world_environment = value
		_refresh()
## The sun whose shadows get finer.
@export var sun: DirectionalLight3D:
	set(value):
		sun = value
		_refresh()
## The baked lightmaps, hidden when `global_light` is SDFGI.
@export var lightmap: LightmapGI:
	set(value):
		lightmap = value
		_refresh()

@export_group("Forward+ extras")
## Turns every extra below on or off together.
@export var enabled := true:
	set(value):
		enabled = value
		_refresh()
## Where bounce light comes from.
@export var global_light: GlobalLight = GlobalLight.BAKED:
	set(value):
		global_light = value
		_refresh()
## Darkens creases and contact points (SSAO).
@export var ambient_occlusion := true:
	set(value):
		ambient_occlusion = value
		_refresh()
## Colour bleeding from lit surfaces onto their neighbours in screen space (SSIL).
@export var indirect_light := true:
	set(value):
		indirect_light = value
		_refresh()
## Reflections of the scene on glossy surfaces (SSR).
@export var reflections := true:
	set(value):
		reflections = value
		_refresh()
## Light shafts and a thick haze that the sun and the shadows shape.
@export var volumetric_fog := true:
	set(value):
		volumetric_fog = value
		_refresh()
## How thick the volumetric haze is.
@export_range(0.0, 0.1, 0.001) var volumetric_density := 0.012:
	set(value):
		volumetric_density = value
		_refresh()
## Brightness: the same scene reads darker in Forward+ than in Compatibility, so this lifts the
## tonemap exposure to match what the web build shows. Set 1 to take the plain tonemap.
@export_range(0.5, 2.0, 0.05) var exposure_match := 1.35:
	set(value):
		exposure_match = value
		_refresh()
## Four shadow cascades, a sharper atlas and softer edges for the sun. Turning it off takes the
## sun's cascades back at once and the atlas the next time the game starts.
@export var finer_shadows := true:
	set(value):
		finer_shadows = value
		_refresh()

## The level's own environment, kept so that applying twice never stacks the extras.
var _source: Environment
## Whether this build draws the extras. Read once; a test sets it to try them on any renderer.
var _supported := is_supported()
## The sun's own shadow distance, kept when the finer shadows first change it.
var _sun_distance := -1.0


## True when this build can draw the extras.
static func is_supported() -> bool:
	return RenderingServer.get_current_rendering_method() == FORWARD_PLUS


func _ready() -> void:
	_refresh()


## Switches the extras on, or off when `enabled` is off (Forward+ only; does nothing otherwise).
func apply() -> void:
	if not _supported:
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
	elif sun != null and _sun_distance >= 0.0:
		sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
		sun.directional_shadow_max_distance = _sun_distance


# Puts the settings on the scene again, in the game only: a setter calls it, so a change made
# while the game runs shows at once.
func _refresh() -> void:
	if not is_node_ready() or Engine.is_editor_hint() or not _supported:
		return
	if enabled:
		apply()
	else:
		_restore()


# Gives the level back its own environment and lightmaps, as they are without the extras.
func _restore() -> void:
	_restore_environment()
	if lightmap != null:
		lightmap.visible = true


func _restore_environment() -> void:
	if world_environment != null and _source != null and is_instance_valid(world_environment):
		world_environment.environment = _source


func _finer_shadows() -> void:
	RenderingServer.directional_shadow_atlas_set_size(4096, true)
	RenderingServer.directional_soft_shadow_filter_set_quality(
		RenderingServer.SHADOW_QUALITY_SOFT_HIGH
	)
	if sun != null:
		if _sun_distance < 0.0:
			_sun_distance = sun.directional_shadow_max_distance
		sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
		sun.directional_shadow_max_distance = 120.0
