## Measures what the weapon hold costs (kit #1001): 40 mannequins play the pistol's aim clip, each
## with `pistol_held.tscn` on its hand, in three runs: no hold scene, the hold carried (the grip's
## finger pose alone) and the hold aimed (the finger pose, the left arm's IK, the hand's turn and
## the left fingers). Each run prints the mean and the slowest process time of a frame and the
## cost of the hold for one character, on lines starting `BENCH`.
##
## `<godot> --headless --path game res://tools/bench/hold_cost.tscn` (the modifiers are skeleton
## work on the CPU, so a headless run measures them; add a window for the draw). It lives in
## tools/, which the export leaves out, and nothing in the game refers to it.
extends Node3D

const FIGURES := 40
const WARM_FRAMES := 150
const MEASURED_FRAMES := 300
const CLIP := &"ual1/Pistol_Aim_Neutral"
const RUNS: Array[Dictionary] = [
	{"name": "no_hold", "hold": false, "aim": 0.0},
	{"name": "carried", "hold": true, "aim": 0.0},
	{"name": "aimed", "hold": true, "aim": 1.0},
]


func _ready() -> void:
	_bench.call_deferred()


func _bench() -> void:
	var base := 0.0
	for run in RUNS:
		var holder := Node3D.new()
		add_child(holder)
		for index in FIGURES:
			var stage := HoldStage.make(holder, "female", run.hold, false)
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
		var mean := total / MEASURED_FRAMES
		if not run.hold:
			base = mean
		print(
			(
				"BENCH %s: %d characters, process %.3f ms a frame (slowest %.3f), hold %.1f us each"
				% [run.name, FIGURES, mean, slowest, (mean - base) * 1000.0 / FIGURES]
			)
		)
		holder.queue_free()
		await get_tree().process_frame
	get_tree().quit()
