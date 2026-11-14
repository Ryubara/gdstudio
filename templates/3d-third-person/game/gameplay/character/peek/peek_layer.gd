class_name PeekLayer
extends Node
## Draws the character's peek lean (gdstudio #1400) on its skeleton: a `PeekModifier` made as a
## child of the model's `Skeleton3D`, before the weapon hold's and the aim layer's modifiers (the
## first of the skeleton's own children; the brace and the momentum blend run before it), so the
## hold closes the hands on the weapon where the bend took it and the aim layer turns the bent
## chest until the muzzle is back on the aim: the pistol and the rifle stay held and on target.
##
## The bend follows `CharacterPeek.drawn()` (the step's lean between the last two physics steps),
## and puts the head bone where the step put the eye: the body's `full_angle()` tilt and its
## `eye_shift()` to the side. Its lean is the body's state (the step's, or a puppet's from the
## network); the bend itself is a pose on each machine. Made again when the model changes.

const _MODIFIER := &"PeekBend"

@export_group("Nodes")
## The character whose lean the skeleton shows.
@export var character: Character
## The slot that holds the character's model.
@export var model: CharacterModel

@export_group("Bend")
## The bones that bend, from the hips up, and each one's share of the roll (adding up to 1).
@export var chain: Array[StringName] = PeekModifier.CHAIN.duplicate()
@export var chain_weights := PackedFloat32Array([0.2, 0.25, 0.25, 0.18, 0.12])
## The bones under the first that keep their turn in the world (the legs stay as the clips put
## them).
@export var keep: Array[StringName] = [&"thigh_l", &"thigh_r"]
## The bone that goes where the body's eye point goes.
@export var head: StringName = &"Head"
## On: no bend (the body still leans: its eye, its shape and the camera move).
@export var disabled := false

var _modifier: PeekModifier


func _ready() -> void:
	if model != null:
		model.rig_changed.connect(_build.unbind(1))
	_build.call_deferred()


func _process(_delta: float) -> void:
	refresh()


## The modifier this node made on the skeleton, or null.
func modifier() -> PeekModifier:
	return _modifier if _modifier != null and is_instance_valid(_modifier) else null


## Puts the lean on the modifier now (the frame's own `_process` does it too).
func refresh() -> void:
	var bend := modifier()
	if bend == null or character == null:
		return
	var share := 0.0 if disabled else character.peek_motion.drawn()
	if bend.active != (share != 0.0):
		bend.active = share != 0.0
	if share == 0.0:
		bend.angle = 0.0
		return
	var eye := CharacterCapsule.eye_height(character)
	var flat := character.peek_motion.eye_shift(character, eye, share)
	var facing := model.global_basis.z if model != null else CharacterPeek.forward_of(character)
	facing = Vector3(facing.x, 0.0, facing.z).normalized()
	var right := facing.cross(Vector3.UP)
	bend.facing = facing
	bend.angle = share * character.peek_motion.full_angle(character, eye)
	bend.shift = right * Vector2(flat.x, flat.z).length() * signf(share)


# Makes the modifier on the model's skeleton, after freeing the one made on the last model, as the
# skeleton's first own child.
func _build() -> void:
	if _modifier != null and is_instance_valid(_modifier):
		_modifier.get_parent().remove_child(_modifier)
		_modifier.queue_free()
	_modifier = null
	var skeleton := model.skeleton() if model != null else null
	if skeleton == null:
		return
	_modifier = PeekModifier.new()
	_modifier.name = _MODIFIER
	_modifier.chain = chain
	_modifier.weights = chain_weights
	_modifier.keep = keep
	_modifier.head = head
	_modifier.active = false
	skeleton.add_child(_modifier)
	skeleton.move_child(_modifier, 0)
	refresh()
