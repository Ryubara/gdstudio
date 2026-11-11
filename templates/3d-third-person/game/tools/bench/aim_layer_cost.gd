## Measures what the aim layer costs (kit #1253): 40 dressed players stand aiming 30 degrees to
## the left of the way they face (so the layer turns the spine every frame), stepped by commands,
## in one of two runs named by the user argument: `off` (the layer disabled) or `on`. It prints the
## mean and the slowest process time of a frame on a line starting `BENCH`; the layer's cost for
## one character is `on`'s mean less `off`'s, over 40.
##
## `<godot> --headless --path game res://tools/bench/aim_layer_cost.tscn -- on` (the modifier is
## skeleton work on the CPU, so a headless run measures it). One run a process. It lives in
## tools/, which the export leaves out, and nothing in the game refers to it.
extends Node3D

const FIGURES := 40
const WARM_FRAMES := 120
const MEASURED_FRAMES := 300

var _players: Array[Player] = []
var _command := PlayerCommand.new()


func _ready() -> void:
	_bench.call_deferred()


func _bench() -> void:
	var arguments := OS.get_cmdline_user_args()
	var run_name := arguments[0] if arguments.size() > 0 else "on"
	var floor_body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(40.0, 1.0, 40.0)
	shape.shape = box
	floor_body.add_child(shape)
	floor_body.position = Vector3(0.0, -0.5, 0.0)
	add_child(floor_body)
	var scene := load("res://gameplay/player/player.tscn") as PackedScene
	for index in FIGURES:
		var player := scene.instantiate() as Player
		player.start_at_spawn = false
		player.position = Vector3(index % 8 - 3.5, 0.0, floorf(index / 8.0) - 2.0) * 2.0
		add_child(player)
		if player.controller != null:
			player.controller.queue_free()
			player.controller = null
		player.set_physics_process(false)
		(player.get_node("AimLayer") as AimLayer).disabled = run_name == "off"
		_players.append(player)
	_command.aim = true
	_command.yaw = deg_to_rad(30.0)
	for _frame in WARM_FRAMES:
		await get_tree().process_frame
	var total := 0.0
	var slowest := 0.0
	for _frame in MEASURED_FRAMES:
		await get_tree().process_frame
		var spent := Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
		total += spent
		slowest = maxf(slowest, spent)
	print(
		(
			"BENCH %s: %d characters, process %.3f ms a frame (slowest %.3f)"
			% [run_name, FIGURES, total / MEASURED_FRAMES, slowest]
		)
	)
	get_tree().quit()


# Steps every body with the aiming command once a tick; the bodies keep facing ahead (the step
# turns them to the view, so the facing is put back), so the layer always has a turn to make.
func _physics_process(delta: float) -> void:
	for player in _players:
		player.step(_command, delta)
		player.facing = 0.0
		player.model.rotation.y = 0.0
