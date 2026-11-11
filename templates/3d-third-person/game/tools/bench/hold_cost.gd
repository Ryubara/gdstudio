## Measures what the weapon hold costs (kit #1001): 40 mannequins play the pistol's aim clip, each
## with `pistol_held.tscn` on its hand, in one of three runs named by the user argument: `no_hold`
## (no hold scene), `carried` (the grip's finger pose, the wrist's turn and the arm's swing) or
## `aimed` (those and the left arm's reach and the left fingers). It prints the mean and the
## slowest process time of a frame on a line starting `BENCH`; the hold's cost for one character
## is a run's mean less `no_hold`'s, over 40.
##
## `<godot> --headless --path game res://tools/bench/hold_cost.tscn -- carried` (the modifiers are
## skeleton work on the CPU, so a headless run measures them). One run a process: a second set of
## 40 mannequins in the same process measured ten times the first with nothing changed. It lives
## in tools/, which the export leaves out, and nothing in the game refers to it.
extends Node3D

const FIGURES := 40
const WARM_FRAMES := 150
const MEASURED_FRAMES := 300
const CLIP := &"ual1/Pistol_Aim_Neutral"
const RUNS: Dictionary[String, Dictionary] = {
	"no_hold": {"hold": false, "aim": 0.0},
	"carried": {"hold": true, "aim": 0.0},
	"aimed": {"hold": true, "aim": 1.0},
}


func _ready() -> void:
	_bench.call_deferred()


func _bench() -> void:
	var arguments := OS.get_cmdline_user_args()
	var run_name := arguments[0] if arguments.size() > 0 else "aimed"
	if not RUNS.has(run_name):
		printerr("hold_cost: the run is one of %s" % ", ".join(RUNS.keys()))
		get_tree().quit(1)
		return
	var run := RUNS[run_name]
	for index in FIGURES:
		var stage := HoldStage.make(self, "female", run.hold, false)
		stage.position = Vector3(index % 8 - 3.5, 0.0, floorf(index / 8.0) - 2.0) * 1.2
		var player := AnimationPlayer.new()
		stage.add_child(player)
		player.root_node = player.get_path_to(stage.slot.rig())
		player.add_animation_library(&"ual1", load(HoldStage.LIBRARIES["ual1"]))
		player.get_animation(CLIP).loop_mode = Animation.LOOP_LINEAR
		player.play(CLIP)
		if stage.hold != null:
			stage.hold.set(&"aim_weight", run.aim)
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
