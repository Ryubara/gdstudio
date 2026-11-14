@tool
class_name EffectDef
extends Resource
## What a one-shot effect is: a particles scene, a sound, a short light flash and how long they
## last. Save one as a `.tres` (or keep it inside a scene) and hand it to the level's
## `EffectEmitter`, which plays it from a pool at a point (`play_at`) or on a node (`play_on`). Any
## feature that wants a flash, a puff or a sound uses this; a weapon's muzzle flash and every bullet
## impact are `EffectDef`s.
##
## Every part is optional: a sound alone, a light alone and particles alone all work. The numbers
## are read each time the effect plays, so a change made while the game runs shows in the next
## play. The particle nodes live in their own scene (open it to restyle them).

@export_group("Particles")
## A scene of one-shot `CPUParticles3D` or `GPUParticles3D` nodes (the root may be one). +Y is the
## way the effect points: along the surface normal at a hit, out of the barrel (the marker's -Z) on
## a muzzle. Prefer `CPUParticles3D`: the web build (Compatibility renderer) builds extra programs
## for a `GPUParticles3D`.
@export var particles: PackedScene

@export_group("Sound")
## The sound that plays at the effect (an `AudioStreamRandomizer` gives variants).
@export var sound: AudioStream
## How loud the sound is.
@export_range(-60.0, 12.0, 0.5, "suffix:dB") var sound_volume_db := -12.0
## The audio bus the sound plays on.
@export var sound_bus: StringName = &"SFX"
## The distance past which the sound cannot be heard.
@export_range(1.0, 500.0, 1.0, "or_greater", "suffix:m") var sound_max_distance := 60.0
## How much the sound darkens as it is heard quieter (the player's `attenuation_filter_db`): -24 is
## Godot's default, 0 turns the filter off. Godot scales it by the heard gain with `sound_volume_db`
## included, so a trimmed sound is darkened near its full amount even up close; the web build
## (samples) ignores it (docs/gamedev/audio/sound-effects.md#fire).
@export_range(-80.0, 0.0, 0.5, "suffix:dB") var sound_filter_db := -24.0

@export_group("Light")
## The brightness of the flash of light at the start. Zero makes no light. The Compatibility
## renderer counts every light against a per-object cap: keep it for a flash that matters.
@export_range(0.0, 16.0, 0.1) var light_energy := 0.0
## The colour of the flash of light.
@export var light_color := Color(1.0, 0.72, 0.38)
## How far the flash of light reaches.
@export_range(0.1, 30.0, 0.1, "or_greater", "suffix:m") var light_range := 4.0
## How long the flash of light lasts; it fades out over this time.
@export_range(0.0, 2.0, 0.005, "suffix:s") var light_time := 0.06
## How fast the light falls off with distance (the light's `omni_attenuation`): 1 is Godot's
## default, below 1 keeps a surface right at the light from getting far brighter than one a metre
## away (a muzzle pressed to a wall), above 1 keeps the light close to where it starts.
@export_exp_easing("attenuation") var light_attenuation := 1.0
## On: a new play of this effect takes the light over from the plays of it still lit, so a fast
## weapon's flashes never stack two lights on the same wall.
@export var light_alone := false

@export_group("Timing")
## How long the effect holds its place in the pool, and then it is cut. Zero waits for the
## particles, the light and the sound to end by themselves.
@export_range(0.0, 30.0, 0.01, "suffix:s") var duration := 0.0
## How many of this effect can show at once. A newer one takes the place of the oldest.
@export_range(1, 32, 1) var max_instances := 4

@export_group("Placement")
## Moves the effect from the point or node it plays on, in that place's own axes.
@export var offset := Vector3.ZERO
## Turns the effect from the way it would point, in degrees.
@export var rotation_degrees := Vector3.ZERO
## Makes the effect bigger or smaller: the particles' scale and the light's reach.
@export_range(0.05, 10.0, 0.05, "or_greater", "suffix:x") var size := 1.0


## The offset and the turn of this effect as one transform.
func local_transform() -> Transform3D:
	var turn := Basis.from_euler(rotation_degrees * (PI / 180.0))
	return Transform3D(turn, offset)
