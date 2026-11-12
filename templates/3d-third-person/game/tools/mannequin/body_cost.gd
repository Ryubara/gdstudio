extends SceneTree
## What a character model costs the processor a frame: its clip, its skeleton and its modifiers
## (kit #1149). It stands a crowd of one model playing the library's walk and times the frames.
##
## Run one model a process (a second crowd in the same process reads many times the first):
##
##     godot --headless --path . -s tools/mannequin/body_cost.gd -- <model.glb> [count]
##         [twist|notwist]
##
## It times the work itself, not the frames (a headless Godot waits between frames): each frame
## it advances every clip and every skeleton by hand, modifiers included, and reads a hand's
## place so the bones are worked out. There is no drawing: what the skin costs the graphics card
## is the vertices and bones of the level of detail on screen.

const LIBRARY := "res://assets/animation/universal/ual1.glb"
const WARM_UP := 60
const FRAMES := 600

var _frame := 0
var _count := 40
var _model := ""
var _spent := 0
var _bones := 0
var _players: Array[AnimationPlayer] = []
var _skeletons: Array[Skeleton3D] = []


func _initialize() -> void:
	var arguments := OS.get_cmdline_user_args()
	_model = arguments[0]
	if arguments.size() > 1:
		_count = int(arguments[1])
	var twist := arguments.size() < 3 or arguments[2] != "notwist"
	var scene: PackedScene = load(_model)
	var library: AnimationLibrary = load(LIBRARY)
	for i in _count:
		var model: Node3D = scene.instantiate()
		model.position = Vector3(i % 8, 0.0, i / 8)
		root.add_child(model)
		var skeleton: Skeleton3D = model.find_children("*", "Skeleton3D", true, false)[0]
		_bones = skeleton.get_bone_count()
		var modifier := skeleton.get_node_or_null("MannequinTwist")
		if modifier != null:
			modifier.skip_beyond = 0.0
			modifier.active = twist
		var player := AnimationPlayer.new()
		model.add_child(player)
		player.add_animation_library(&"ual1", library)
		player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
		skeleton.modifier_callback_mode_process = Skeleton3D.MODIFIER_CALLBACK_MODE_PROCESS_MANUAL
		player.play(&"ual1/Walk")
		player.seek(i * 0.037)
		_players.append(player)
		_skeletons.append(skeleton)


func _process(_delta: float) -> bool:
	_frame += 1
	var started := Time.get_ticks_usec()
	for i in _count:
		_players[i].advance(1.0 / 60.0)
		_skeletons[i].advance(1.0 / 60.0)
		_skeletons[i].get_bone_global_pose(_skeletons[i].find_bone("hand_r"))
	if _frame > WARM_UP:
		_spent += Time.get_ticks_usec() - started
	if _frame == WARM_UP + FRAMES:
		var each := float(_spent) / FRAMES / _count
		print(
			(
				"COST %s: %d bones, %.1f microseconds a character a frame (%d characters)"
				% [_model.get_file(), _bones, each, _count]
			)
		)
		return true
	return false
