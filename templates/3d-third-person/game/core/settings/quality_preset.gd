class_name QualityPreset
extends Resource
## One step of the video quality choice: what it sets on the renderer. The `Settings` autoload holds
## three of them (Low, Medium, High) and applies the one the player picked; change the numbers in
## its inspector and the running game follows the next time the preset is applied.
##
## Only settings the Compatibility renderer (the web build, phones) honours live here, so the same
## presets serve every platform.

## The word the settings screen shows.
@export var title := "High"
## Multisample anti-aliasing of the 3D view.
@export var msaa: Viewport.MSAA = Viewport.MSAA_2X
## Size of the sun's shadow map in pixels, a power of two: bigger is sharper and costs memory.
@export_range(1024, 8192, 1, "suffix:px") var shadow_atlas_size := 4096
## How soft the edge of a shadow is: harder is cheaper.
@export var shadow_filter: RenderingServer.ShadowQuality = RenderingServer.SHADOW_QUALITY_SOFT_HIGH
