## Measures what the weapon holds cost (kit #1001, #1178): 40 mannequins play the pistol's aim clip,
## each with `pistol_held.tscn` on its hand, in one of the runs named by the user argument (or by
## `?run=` in the web build's address): `no_hold` (no hold scene), `carried` (the grip's finger
## pose, the wrist's turn and the arm's swing) or `aimed` (those and the left arm's reach and the
## left fingers); or with `rifle_held.tscn` in the model's space: `rifle` (aimed: the stance, both
## arms' reach and both hands' fingers), `rifle_low` (the same at the low ready) or `rifle_reload`
## (aimed, 0.3 of a reload: the left hand taking the magazine out) or `rifle_far`
## (aimed, seen by a camera 30 m away: past the hold's `fingers_far_distance`).
##
## A frame's work is the span from the `_process` of the first node to process to the end of the
## deferred calls that follow the last one (the skeletons run their modifiers there), the same
## code headless and in a browser. It prints the mean and the median on a line starting `BENCH`
## and, in a browser, puts them in `window.__hold_cost`; the hold's cost for one character is a
## run's mean less `no_hold`'s, over 40.
##
## `<godot> --headless --path game res://tools/bench/hold_cost.tscn -- rifle` (the modifiers are
## skeleton work on the CPU, so a headless run measures them); in Chrome,
## `gds template bench-web 3d-third-person hold_cost --run` (`hold_cost.py` reads every run). One
## run a process: a second set of 40 mannequins in the same process measured ten times the first
## with nothing changed. It builds its figures itself (the export leaves `tests/` out) and lives
## in tools/, which the game's export leaves out; nothing in the game refers to it.
extends Node3D

const FIGURES := 40
const WARM_FRAMES := 150
const MEASURED_FRAMES := 600
const CLIP := &"ual1/Pistol_Aim_Neutral"
const LIBRARY := "res://assets/animation/universal/ual1.glb"
const MODEL := "res://assets/characters/mannequin/mannequin_female.glb"
const PISTOL_HELD := "res://assets/weapons/pistol/pistol_held.tscn"
const PISTOL_HOLD := "res://gameplay/weapon/hold/weapon_hold.tscn"
const RIFLE_HELD := "res://gameplay/weapon/rifle_held.tscn"
const RUNS: Dictionary[String, Dictionary] = {
	"no_hold": {"hold": false, "aim": 0.0},
	"carried": {"hold": true, "aim": 0.0},
	"aimed": {"hold": true, "aim": 1.0},
	"rifle": {"rifle": true, "aim": 1.0},
	"rifle_low": {"rifle": true, "aim": 0.0},
	"rifle_reload": {"rifle": true, "aim": 1.0, "reload": 0.3},
	"rifle_far": {"rifle": true, "aim": 1.0, "camera": 30.0},
}

var _frame_start := 0
var _works := PackedFloat64Array()
var _measuring := false


func _ready() -> void:
	process_priority = -(1 << 30)
	_bench.call_deferred()


func _process(_delta: float) -> void:
	if _measuring:
		_frame_start = Time.get_ticks_usec()


func _bench() -> void:
	var run_name := _run_name()
	if not RUNS.has(run_name):
		printerr("hold_cost: the run is one of %s" % ", ".join(RUNS.keys()))
		get_tree().quit(1)
		return
	var run := RUNS[run_name]
	if run.has("camera"):
		var camera := Camera3D.new()
		add_child(camera)
		camera.position = Vector3(0.0, 2.0, run.camera)
		camera.make_current()
	var library := load(LIBRARY) as AnimationLibrary
	library.get_animation(CLIP.get_slice("/", 1)).loop_mode = Animation.LOOP_LINEAR
	for index in FIGURES:
		var figure := _figure(run)
		figure.position = Vector3(index % 8 - 3.5, 0.0, floorf(index / 8.0) - 2.0) * 1.2
		var player := AnimationPlayer.new()
		figure.add_child(player)
		var slot := figure.get_child(0) as CharacterModel
		player.root_node = player.get_path_to(slot.rig())
		player.add_animation_library(&"ual1", library)
		player.play(CLIP)
	var last := FrameEnd.new()
	last.process_priority = 1 << 30
	last.bench = self
	add_child(last)
	for _frame in WARM_FRAMES:
		await get_tree().process_frame
	_measuring = true
	while _works.size() < MEASURED_FRAMES:
		await get_tree().process_frame
	_measuring = false
	var sorted := _works.duplicate()
	sorted.sort()
	var total := 0.0
	for work in _works:
		total += work
	var result := {
		"run": run_name,
		"characters": FIGURES,
		"frames": _works.size(),
		"mean_ms": total / _works.size(),
		"median_ms": sorted[sorted.size() / 2],
	}
	print(
		(
			"BENCH %s: %d characters, work %.3f ms a frame (median %.3f)"
			% [run_name, FIGURES, result.mean_ms, result.median_ms]
		)
	)
	if OS.has_feature("web"):
		JavaScriptBridge.eval("window.__hold_cost = %s;" % JSON.stringify(result), true)
		return
	get_tree().quit()


## Ends the frame's span: called deferred from the last node's `_process`, after the skeletons'
## own deferred update.
func end_frame() -> void:
	if _measuring and _frame_start > 0:
		_works.append((Time.get_ticks_usec() - _frame_start) / 1000.0)


func _run_name() -> String:
	if OS.has_feature("web"):
		var query := str(JavaScriptBridge.eval("window.location.search", true))
		for pair in query.trim_prefix("?").split("&"):
			if pair.begins_with("run="):
				return pair.trim_prefix("run=")
		return "rifle"
	var arguments := OS.get_cmdline_user_args()
	return arguments[0] if arguments.size() > 0 else "rifle"


# A mannequin in a model slot under a figure node, holding the run's weapon.
func _figure(run: Dictionary) -> Node3D:
	var figure := Node3D.new()
	add_child(figure)
	var slot := CharacterModel.new()
	figure.add_child(slot)
	slot.add_child((load(MODEL) as PackedScene).instantiate())
	if run.get("rifle", false):
		var held := (load(RIFLE_HELD) as PackedScene).instantiate() as TwoHandHold
		held.posed_aim = run.aim
		held.posed_reload = run.get("reload", -1.0)
		slot.add_child(held)
		return figure
	var seat := (load(PISTOL_HELD) as PackedScene).instantiate() as BoneAttachment3D
	slot.add_child(seat)
	seat.use_external_skeleton = true
	seat.external_skeleton = seat.get_path_to(slot.skeleton())
	if run.hold:
		var hold := (load(PISTOL_HOLD) as PackedScene).instantiate()
		hold.set(&"model", slot)
		hold.set(&"seat", seat)
		hold.set(&"aim_weight", run.aim)
		figure.add_child(hold)
	return figure


# The node that processes last and closes the frame's span after the deferred calls.
class FrameEnd:
	extends Node

	var bench: Node

	func _process(_delta: float) -> void:
		if bench != null:
			bench.call_deferred(&"end_frame")
