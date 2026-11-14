## Films first shots on a wall from the game camera, with the HUD (gdstudio #1411): the rifle, the
## crosshair held still on one point of a wall 15 m ahead, five single taps with the aim held and
## a rest between them (every one lands on the crosshair's point), three taps from the hip (the
## arm comes up and the shot lands there too), then the trigger held for a second (the spread
## grows over the shots in a row). It presses the input actions the way a player would and prints
## how far each shot landed from the crosshair's point (`SHOT <n> <cm off>`), and puts a small
## coloured dot where each shot met the wall, around a green cross drawn at the crosshair's point
## in place of the HUD's crosshair (from the first shot on).
##
## Record it with Movie Maker through the kit (the frames land in the scratch folder):
## `gds capture frames --project game --scene res://tools/capture/first_shot_tour.tscn --seconds 11
## --fps 30`
## It lives in tools/, which the export leaves out, and nothing in the game refers to it.
extends Node

## A flat floor built high above the map, and where the character stands on it.
const FLOOR_AT := Vector3(0.0, 300.0, 0.0)
const START := Vector3(0.0, 300.1, 0.0)
## The wall's face, ahead of the character.
const WALL_AT := 15.0
const PITCH := 3.0
## One physics tick: the shortest press a player can make.
const TAP := 1.0 / 60.0
## The dots' colours by stage after "ready": aimed taps, (down), hip taps, held.
const MARK_COLOURS: Array[Color] = [Color.RED, Color.RED, Color.ORANGE, Color.DODGER_BLUE]

## Each stage: `name` (printed when it starts), `hold` the actions held, `seconds` how long, and
## `taps`: actions pressed for `tap` seconds (one tick by default) at each of the listed seconds.
const STAGES: Array[Dictionary] = [
	{"name": "ready", "hold": [], "seconds": 1.0},
	{
		"name": "aimed taps from rest",
		"hold": [&"aim"],
		"seconds": 4.2,
		"taps": {&"fire": [0.6, 1.3, 2.0, 2.7, 3.4]},
	},
	{"name": "down", "hold": [], "seconds": 0.8},
	{"name": "hip taps", "hold": [], "seconds": 3.0, "taps": {&"fire": [0.1, 1.1, 2.1]}},
	{
		"name": "held one second",
		"hold": [&"aim"],
		"seconds": 2.0,
		"taps": {&"fire": [0.6]},
		"tap": 1.0,
	},
]

var _index := -1
var _clock := 0.0
var _held: Array[StringName] = []
var _shots := 0

@onready var _player: Player = $Main/PlayerRig/Player
@onready var _rig: PlayerCamera = $Main/PlayerRig/PlayerCamera


func _ready() -> void:
	var block := load("res://world/blocks/proto_block.tscn") as PackedScene
	var floor_block := block.instantiate()
	floor_block.size = Vector3(40.0, 1.0, 40.0)
	floor_block.position = FLOOR_AT - Vector3(0.0, 0.5, 0.0)
	add_child(floor_block)
	var wall := block.instantiate()
	wall.size = Vector3(12.0, 6.0, 0.4)
	wall.position = FLOOR_AT + Vector3(0.0, 3.0, -WALL_AT - 0.2)
	add_child(wall)
	var rifle := (load("res://gameplay/weapon/rifle.tres") as WeaponDef).duplicate() as WeaponDef
	rifle.auto_reload = false
	_player.loadout.give(rifle, 60)
	_player.teleport(START, 0.0)
	_rig.yaw = 0.0
	_rig.pitch = PITCH
	_player.weapon.fired.connect(_on_fired)


func _on_fired(_shot: Projectile) -> void:
	var weapon := _player.weapon
	var ray := _player.aim_ray()
	var face := FLOOR_AT.z - WALL_AT
	var aimed := ray[0] + ray[1] * ((face - ray[0].z) / ray[1].z)
	var start := weapon.last_origin
	var heading := weapon.last_heading
	var hit := start + heading * ((face - start.z) / heading.z)
	_shots += 1
	if _shots == 1:
		_cross(aimed + Vector3(0.0, 0.0, 0.01))
	_mark(hit + Vector3(0.0, 0.0, 0.03))
	var cone: Variant = weapon.get(&"spread_now")
	print("SHOT ", _shots, " %.1f cm, next cone %s deg" % [hit.distance_to(aimed) * 100.0, cone])


# A thin green cross on the wall where the crosshair's ray meets it, drawn in place of the HUD's
# crosshair, whose disc would hide the dots under it (36 cm across at 15 m with the aim's view).
func _cross(at: Vector3) -> void:
	for size in [Vector3(0.6, 0.012, 0.01), Vector3(0.012, 0.6, 0.01)]:
		var bar := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = size
		var paint := StandardMaterial3D.new()
		paint.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		paint.albedo_color = Color(0.1, 0.7, 0.2)
		box.material = paint
		bar.mesh = box
		add_child(bar)
		bar.global_position = at
	for crosshair in get_tree().root.find_children("Crosshair", "", true, false):
		(crosshair as CanvasItem).modulate.a = 0.0


# A small dot where a shot met the wall, coloured by the stage (the wall's own marks are hidden
# under the crosshair): red aimed from rest, orange from the hip, blue the held trigger.
func _mark(at: Vector3) -> void:
	var dot := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.025
	sphere.height = 0.05
	var paint := StandardMaterial3D.new()
	paint.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	paint.albedo_color = MARK_COLOURS[clampi(_index - 1, 0, MARK_COLOURS.size() - 1)]
	sphere.material = paint
	dot.mesh = sphere
	add_child(dot)
	dot.global_position = at


func _physics_process(delta: float) -> void:
	if _index >= STAGES.size():
		return
	if _index < 0 or _clock >= float(STAGES[_index]["seconds"]):
		_index += 1
		_clock = 0.0
		if _index >= STAGES.size():
			_finish()
			return
		print("STAGE ", STAGES[_index]["name"], " ", Engine.get_physics_frames())
	var stage := STAGES[_index]
	var actions: Array[StringName] = []
	actions.append_array(stage["hold"])
	var taps: Dictionary = stage.get("taps", {})
	var length: float = stage.get("tap", TAP)
	for action: StringName in taps:
		for at: float in taps[action]:
			if _clock >= at - 1e-4 and _clock < at + length - 1e-4:
				actions.append(action)
	_clock += delta
	_hold(actions)


# Stops the sounds and gives the mixer a few frames to let go of them before the capture quits.
func _finish() -> void:
	_hold([])
	set_physics_process(false)
	AudioSettings.stop_players(get_tree().root)
	for _frame in 8:
		await get_tree().process_frame
	get_tree().quit()


# Holds exactly these actions down and lets go of the rest.
func _hold(actions: Array[StringName]) -> void:
	for action in _held:
		if not actions.has(action):
			Input.action_release(action)
	_held.clear()
	for action in actions:
		Input.action_press(action)
		_held.append(action)
