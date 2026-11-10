@tool
class_name ImpactSurface
extends Node
## One kind of surface and what a shot does to it: whether it takes a mark and which, the effect
## that bursts at the hit and the sound that plays there. `Impacts` holds one per kind
## (`Default`, `Wood`, `Metal`...) and picks it by `surface_name`.
##
## The effect and the sound are nodes under this one that you restyle in the editor: `effect` is
## any `Node3D` with a `restart()` (a `CPUParticles3D` or `GPUParticles3D`, set to one shot), and
## `sound` an `AudioStreamPlayer3D`. They are templates: each hit plays a pooled copy of them
## (`pool_size`, so bursts of shots do not cut each other off), copied again from the template on
## every hit, so a change to the template while the game runs shows in the next hit.
##
## A body says what it is made of with the metadata `surface` (a name, set in the Inspector's
## Metadata section of the body or of any node above it) or by being in a group of that name.

## What a hit on this surface made.
signal played(point: Vector3, normal: Vector3)

## The properties of a template that are not copied onto a pooled copy.
const NOT_COPIED: Array[StringName] = [
	&"name",
	&"owner",
	&"script",
	&"transform",
	&"top_level",
	&"visible",
	&"emitting",
	&"autoplay",
	&"unique_name_in_owner",
	&"scene_file_path",
]

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
## The effect that bursts at the hit, +Y along the surface's normal: a `CPUParticles3D` or
## `GPUParticles3D` child of this node, one shot. Empty makes none.
@export var effect: Node3D
## The sound that plays at the hit: an `AudioStreamPlayer3D` child of this node. Empty makes none.
@export var sound: AudioStreamPlayer3D
## How many hits of this surface can show and sound at once; a faster burst takes the oldest.
@export_range(1, 16, 1) var pool_size := 4

var _effects: Array[Node3D] = []
var _sounds: Array[AudioStreamPlayer3D] = []
var _next_effect := 0
var _next_sound := 0


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	# The templates stay quiet: only their copies play.
	if effect != null and "emitting" in effect:
		effect.set("emitting", false)
	if sound != null:
		sound.autoplay = false


## Shows the effect and plays the sound at `point`, the effect standing on `normal`.
func play(point: Vector3, normal: Vector3, with_effect := true, with_sound := true) -> void:
	if Engine.is_editor_hint():
		return
	if with_effect and effect != null:
		_play_effect(point, normal)
	if with_sound and sound != null:
		_play_sound(point)
	played.emit(point, normal)


## The effect copies made so far (empty until the first hit).
func effect_copies() -> Array[Node3D]:
	return _effects


## The sound copies made so far (empty until the first hit).
func sound_copies() -> Array[AudioStreamPlayer3D]:
	return _sounds


func _play_effect(point: Vector3, normal: Vector3) -> void:
	var copy := _take(_effects, effect, _next_effect) as Node3D
	_next_effect += 1
	_copy_properties(effect, copy)
	copy.global_transform = Transform3D(Basis(Quaternion(Vector3.UP, normal)), point)
	if copy.has_method(&"restart"):
		copy.call(&"restart")
	elif "emitting" in copy:
		copy.set("emitting", true)


func _play_sound(point: Vector3) -> void:
	var copy := _take(_sounds, sound, _next_sound) as AudioStreamPlayer3D
	_next_sound += 1
	_copy_properties(sound, copy)
	copy.global_position = point
	copy.play()


# The pooled copy at `index` (made from `template` while the pool is below `pool_size`). A pool
# that is larger than `pool_size` (it was lowered) is cut back as copies are taken.
func _take(pool: Array, template: Node3D, index: int) -> Node3D:
	while pool.size() > pool_size:
		var surplus := pool.pop_back() as Node
		surplus.queue_free()
	if pool.size() < pool_size:
		var made := template.duplicate() as Node3D
		made.top_level = true
		add_child(made)
		pool.append(made)
		return made
	return pool[index % pool.size()]


# Copies what was edited on the template onto a copy, so a change made while the game runs (a
# colour, an amount, a stream, a volume) shows in the next hit. Only a property that differs is
# written: setting some of them (a particle `amount`) rebuilds buffers.
func _copy_properties(from: Node, to: Node) -> void:
	for property in from.get_property_list():
		var usage: int = property["usage"]
		var property_name: StringName = property["name"]
		if not usage & PROPERTY_USAGE_STORAGE or NOT_COPIED.has(property_name):
			continue
		if String(property_name).contains("/"):
			continue
		var value: Variant = from.get(property_name)
		if to.get(property_name) != value:
			to.set(property_name, value)


func _get_configuration_warnings() -> PackedStringArray:
	var warnings := PackedStringArray()
	if surface_name == &"":
		warnings.append("Set `surface_name`: the name a body gives to be this surface.")
	if effect != null and not effect.has_method(&"restart"):
		warnings.append(
			"`effect` needs a `restart()` method: use a CPUParticles3D or GPUParticles3D."
		)
	return warnings
