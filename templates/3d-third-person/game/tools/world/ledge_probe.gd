extends SceneTree
## Prints how high a ledge the real player body gets onto from level ground, one line a height,
## and the highest it climbed (`ReachBench`; the number `tests/world/test_jump_reach.gd` pins).
##
## Run: godot --headless --fixed-fps 60 --path game -s res://tools/world/ledge_probe.gd


func _initialize() -> void:
	await process_frame
	var heights: Array[float] = []
	for centimetres in range(100, 200, 5):
		heights.append(centimetres / 100.0)
	var bench := ReachBench.new()
	root.add_child(bench)
	var climbed := await bench.measure(heights)
	for height in heights:
		print("LEDGE %.2f climbed %s" % [height, climbed[height]])
	var tuning := CharacterTuning.new()
	print(
		(
			"REACH %.2f m (jump_height %.2f, step_height %.2f, radius %.2f)"
			% [ReachBench.highest(climbed), tuning.jump_height, tuning.step_height, tuning.radius]
		)
	)
	quit()
