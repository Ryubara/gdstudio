## Films the ragdoll the way a person tries it: the character sprints at the ragdoll spot's ledge,
## Y is pressed in the air (the key goes through the engine's input path, so the binding is what
## is filmed), the camera orbits the body as it falls and comes to rest, and Y is pressed again to
## get up. The input is the same a player's: actions held, keys sent, the camera turned with the
## `orbit()` the mouse uses.
##
## Record it with Movie Maker through the kit (the frames land in the scratch folder):
## `gds capture frames --project game --scene res://tools/capture/ragdoll_tour.tscn --seconds 14
## --fps 30`, and with the male mannequin by `-- --male` after the arguments Godot is given. It
## lives in tools/, which the export leaves out, and nothing in the game refers to it.
extends Node

const MALE := "res://assets/characters/mannequin/mannequin_male.glb"
## Where the run starts (the top of the ledge's run-up), the point it runs at, and how long the
## character runs before Y.
const START := Vector3(-14.0, 0.0, 9.0)
const RUN_TO := Vector3(-14.0, 0.0, 15.0)
## Degrees a second the camera turns while the body lies.
const ORBIT_SPEED := 70.0

## The beats, in seconds from the start: Y is pressed to fall, the camera orbits, Y again to get up.
@export var run_seconds := 1.4
@export var lie_seconds := 4.2
@export var up_seconds := 3.0

var _clock := 0.0
var _phase := 0
var _held: Array[StringName] = []

@onready var _player: Player = $Main/Player
@onready var _rig: PlayerCamera = $Main/PlayerCamera


func _ready() -> void:
	if "--male" in OS.get_cmdline_user_args():
		_swap_to_male()
	#_player.teleport(START, 0.0)
	_rig.yaw = 0.0
	_rig.pitch = 12.0
	_player.died.connect(func() -> void: print("TOUR died at ", _clock))
	_player.revived.connect(func() -> void: print("TOUR revived at ", _clock))


func _physics_process(delta: float) -> void:
	_clock += delta
	match _phase:
		0:
			_hold([&"move_forward", &"sprint"])
			if _clock >= run_seconds:
				_press_key(KEY_Y)
				_phase = 1
				_clock = 0.0
		1:
			_hold([])
			_rig.orbit(Vector2(-ORBIT_SPEED * delta, 0.0))
			if _clock >= lie_seconds:
				_press_key(KEY_Y)
				_phase = 2
				_clock = 0.0
		2:
			if _clock >= up_seconds:
				get_tree().quit()


# The editor's swap: delete the model, drop the other mannequin on the slot.
func _swap_to_male() -> void:
	var slot := _player.model
	var old := slot.rig()
	var animation_player: AnimationPlayer = _player.get_node("AnimationPlayer")
	var tree: AnimationTree = _player.get_node("AnimationTree")
	slot.remove_child(old)
	old.free()
	animation_player.root_node = NodePath()
	tree.root_node = NodePath()
	var added := (load(MALE) as PackedScene).instantiate() as Node3D
	slot.add_child(added)
	added.owner = _player


func _press_key(code: Key) -> void:
	for pressed in [true, false]:
		var event := InputEventKey.new()
		event.keycode = code
		event.physical_keycode = code
		event.pressed = pressed
		Input.parse_input_event(event)
		Input.flush_buffered_events()


func _hold(actions: Array) -> void:
	for action in _held:
		if not actions.has(action):
			Input.action_release(action)
	_held.clear()
	for action: StringName in actions:
		Input.action_press(action)
		_held.append(action)
