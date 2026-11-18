# Lying down with the rifle eases its hold and its sight head out with the stow (gdstudio #1581):
# from a crouch, from standing and from a run, and getting up again, no drawn bone moves further in
# a tick than it does in the same change with the pistol, plus `MoveResponse.POSE_JUMP_PLUS`. The
# bound is the pistol's own lie-down, not the rifle's clip played alone: before the fix that clip
# read as a reference held the very jump it should have caught. Each tick is measured in
# `skeleton_updated` (`MoveResponse`), so the modifiers after the tree count.
#
# Before the fix the rifle's hold and its `AimHead.SIGHT` head let go in the one tick the stow share
# passed 0.5 and `WeaponLayers.drive` hid the rifle: the head dropped 0.48 m in a tick, 16 ticks
# after the press from a crouch, where the ticks around it moved 0.10 to 0.17 m.
extends GdUnitTestSuite

# Ticks after the press measured: lying down (0.5 s), then the hold's last ease and a rest.
const _TICKS := 70
# The changes, as `MoveResponse.run()` steps at a gait, and the step of the press measured.
const _CASES := [
	["from a crouch", "crouch", [["", 60], ["", 2, "prone"], ["", _TICKS]], 1],
	["from standing", "jog", [["", 60], ["", 2, "prone"], ["", _TICKS]], 1],
	["from a run", "jog", [["W", 80], ["W", 2, "prone"], ["W", _TICKS]], 1],
	[
		"getting up",
		"jog",
		[["", 10], ["", 2, "prone"], ["", 80], ["", 2, "prone"], ["", _TICKS]],
		3
	],
]

var _arena: PlayArena
var _matrix: MoveKeyMatrix
var _response: MoveResponse


func before_test() -> void:
	InputSim.release_all()
	_arena = auto_free(PlayArena.new())
	add_child(_arena)
	_arena.add_block(Vector2.ZERO, Vector3(400.0, 1.0, 400.0), 0.0)
	var player := _arena.add_player(Vector3.ZERO)
	player.tuning = (
		(load("res://gameplay/player/player_tuning.tres") as CharacterTuning).duplicate()
	)
	player.tuning.crouch_toggle = false
	player.set_physics_process(false)
	var camera := Camera3D.new()
	camera.position = Vector3(0.0, 40.0, 0.0)
	_arena.add_child(camera)
	camera.make_current()
	_matrix = MoveKeyMatrix.new()
	_matrix.player = player
	_matrix.input = player.controller as PlayerInput
	_matrix.animation = player.get_node("Animation")
	_matrix.camera = camera
	_matrix.tree = get_tree()
	_response = MoveResponse.new()
	_response.matrix = _matrix
	await InputSim.ticks(get_tree(), 4)
	_matrix.animation.set_throttled(true)


func after_test() -> void:
	InputSim.release_all()
	AudioDrain.stop_all(_arena)


func test_the_rifle_lies_down_as_smoothly_as_the_pistol() -> void:
	var pistol := await _peaks("pistol")
	_matrix.player.loadout.give(load("res://gameplay/weapon/rifle.tres") as WeaponDef, 30)
	await _response.run("jog", 0.0, [["", 90]], 0.0, true)
	assert_str(String(_matrix.player.weapon.definition.resource_path)).ends_with("rifle.tres")
	var rifle := await _peaks("rifle")
	var failures: PackedStringArray = []
	for change: String in pistol:
		var allowed: float = pistol[change].x + MoveResponse.POSE_JUMP_PLUS
		var line := (
			"%s: rifle %.3f m at t+%d, pistol %.3f m, allowed %.3f"
			% [change, rifle[change].x, int(rifle[change].y), pistol[change].x, allowed]
		)
		print("RIFLE_STOW ", line)
		if rifle[change].x > allowed:
			failures.append(line)
	assert_array(failures).is_empty()


# The fists, which have no hold to stow, lie down as the pistol does, whose grip the weapon layer
# fades with the stow (`WeaponLayers.drive`): the same bound, each way, so a change to the stow
# that reached either shows here. Their moves a tick were the same before and after the fix.
func test_the_fists_lie_down_as_the_pistol_does() -> void:
	var pistol := await _peaks("pistol")
	_matrix.player.loadout.toggle_unarmed()
	await _response.run("jog", 0.0, [["", 90]], 0.0, true)
	var held := _matrix.player.loadout.held_definition()
	assert_bool(held == null or held.resource_path.ends_with("fists.tres")).is_true()
	var fists := await _peaks("fists")
	for change: String in pistol:
		print(
			(
				"RIFLE_STOW %s: pistol %.3f m, fists %.3f m"
				% [change, pistol[change].x, fists[change].x]
			)
		)
		assert_float(absf(fists[change].x - pistol[change].x)).is_less(MoveResponse.POSE_JUMP_PLUS)


# Each case's largest move of a drawn bone in a tick over `_TICKS` ticks from its press, and the
# tick it was at (x metres, y ticks after the press); `GDS_POSE_TRACE` prints every tick.
func _peaks(weapon: String) -> Dictionary:
	var peaks := {}
	for case: Array in _CASES:
		var steps: Array = case[2].duplicate()
		if _lies_after(steps):
			steps.append_array([["", 2, "prone"], ["", 90]])
		var samples := await _response.run(case[1], 0.0, steps, 0.0, true)
		var at := -1
		for index in samples.size():
			if samples[index].step == case[3]:
				at = index
				break
		var peak := Vector2(0.0, -1.0)
		var trace: PackedStringArray = []
		for index in range(at, mini(at + _TICKS, samples.size())):
			var moved: float = samples[index].jump
			trace.append("%.3f" % moved)
			if moved > peak.x:
				peak = Vector2(moved, index - at)
		if OS.get_environment("GDS_POSE_TRACE") != "":
			print("RIFLE_STOW_TRACE %s %s: %s" % [weapon, case[0], ", ".join(trace)])
		peaks[case[0]] = peak
	return peaks


# True when `steps` leave the body lying (an odd number of prone presses).
static func _lies_after(steps: Array) -> bool:
	var presses := 0
	for step: Array in steps:
		if step.size() > 2 and String(step[2]).contains("prone"):
			presses += 1
	return presses % 2 == 1
