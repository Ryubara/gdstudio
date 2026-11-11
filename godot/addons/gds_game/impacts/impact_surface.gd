@tool
class_name ImpactSurface
extends Node
## One kind of surface and what a shot does to it: whether it takes a mark and which, and the
## effect (particles and sound) that plays at the hit. `Impacts` holds one per kind (`Default`,
## `Wood`, `Metal`...) and picks it by `surface_name`.
##
## The effect is an `EffectDef`, played by the level's `EffectEmitter` from its pool, the same way
## a muzzle flash is. Open the `EffectDef` in the inspector to change its sound, its light and its
## length, and open its particles scene to restyle the burst. With no `EffectEmitter` in the level
## a hit still leaves its mark.
##
## A body says what it is made of with the metadata `surface` (a name, set in the Inspector's
## Metadata section of the body or of any node above it) or by being in a group of that name.

## What a hit on this surface made.
signal played(point: Vector3, normal: Vector3)

@export_group("Surface")
## The name a body gives (metadata `surface`, or a group) to be this surface.
@export var surface_name: StringName = &"default"

@export_group("Mark")
## On: a hit on this surface leaves a mark. Off for something that moves in a way a mark cannot
## follow (a board that tips over).
@export var leaves_mark := true
## The material of the marks on this surface. Empty uses `Impacts.mark_material`.
@export var mark_material: Material
## The size of this surface's marks, as a multiple of `Impacts.mark_size`.
@export_range(0.1, 4.0, 0.05, "or_greater", "suffix:x") var mark_scale := 1.0

@export_group("Effect")
## What plays at the hit, +Y along the surface's normal: particles and a sound, played by the
## level's `EffectEmitter`. Empty makes none.
@export_custom(PROPERTY_HINT_RESOURCE_TYPE, "EffectDef") var effect: Resource


func _ready() -> void:
	if Engine.is_editor_hint() or effect == null:
		return
	var emitter := EffectEmitter.find(self)
	if emitter != null:
		emitter.warm(effect)


## Plays the effect at `point`, standing on `normal`. `with_effect` and `with_sound` leave out the
## particles or the sound.
func play(point: Vector3, normal: Vector3, with_effect := true, with_sound := true) -> void:
	if Engine.is_editor_hint():
		return
	if effect != null and (with_effect or with_sound):
		var emitter := EffectEmitter.find(self)
		if emitter != null:
			emitter.play_at(effect, point, normal, with_effect, with_sound)
	played.emit(point, normal)


func _get_configuration_warnings() -> PackedStringArray:
	var warnings := PackedStringArray()
	if surface_name == &"":
		warnings.append("Set `surface_name`: the name a body gives to be this surface.")
	return warnings
