# GDStudio's own reversals, pivots and turns on the spot (`assets/animation/own/`, kit #1157):
# `Jog_Turn_180` and `Sprint_Turn_180` planting on each foot, `Jog_Turn_90` and the turns on the
# spot to each side. Each begins and ends on the poses of the clips it joins (the gait, or the
# idle), moving as they move; its turn curve ends on its angle and only grows, so the tree can
# play it by how far the body has turned; the two clips of a pair are not mirror images; the
# player plays them (and prints the largest move of a bone between two frames, for #1416).
# Planted feet on the floor the root travels and turns over, skin on the floor, tracks, limbs and
# the budget are `test_own_clips.gd`'s, which reads every clip.
extends GdUnitTestSuite

const OWN := "res://assets/animation/own/locomotion.glb"
const RECORDS := "res://assets/animation/own/locomotion.json"
## Each type: the gait it joins at both ends (or the idle), the angle the `_L` clip turns (degrees,
## to the left), and whether its side is the foot that plants (a reversal) or the way it turns.
const TYPES := {
	"Jog_Turn_90": ["Jog", 90.0],
	"Jog_Turn_180": ["Jog", 180.0],
	"Sprint_Turn_180": ["Sprint", 180.0],
	"Turn_In_Place_90": ["Idle", 90.0],
	"Turn_In_Place_180": ["Idle", 180.0],
}
const FEET: Array[String] = ["L", "R"]
## The furthest a bone's step over the frame at a join may be from the joined clip's step (m),
## as for the starts and stops.
const JOIN_STEP := 0.012
## How far apart a pair's two clips must be, read as mirror images, at the worst bone (m).
const NOT_A_MIRROR := 0.01

var _model: Node3D
var _skeleton: Skeleton3D
var _player: AnimationPlayer


func _records() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(RECORDS)).clips


func _stage(model_path: String) -> void:
	_model = auto_free((load(model_path) as PackedScene).instantiate())
	add_child(_model)
	_skeleton = _model.find_children("*", "Skeleton3D", true, false)[0]
	_player = auto_free(AnimationPlayer.new())
	add_child(_player)
	_player.root_node = _player.get_path_to(_model)
	_player.add_animation_library(&"gds", load(OWN))


func _places(clip: String, frame: float) -> Dictionary:
	_player.play(StringName("gds/" + clip))
	_player.seek(frame / 30.0, true)
	_player.pause()
	var out := {}
	for bone in _skeleton.get_bone_count():
		out[_skeleton.get_bone_name(bone)] = _skeleton.get_bone_global_pose(bone).origin
	return out


# Metres a second the root travels at over the first or the last two keys of its travel curve.
func _speed(record: Dictionary, last: bool) -> float:
	var curve: Array = record.travel
	var a: Array = curve[-2] if last else curve[0]
	var b: Array = curve[-1] if last else curve[1]
	return Vector2(b[1] - a[1], b[2] - a[2]).length() / ((b[0] - a[0]) / 30.0)


func test_every_turn_has_both_clips_and_a_turn_curve_the_tree_can_read() -> void:
	var records := _records()
	var library: AnimationLibrary = load(OWN)
	for base: String in TYPES:
		var joined: String = TYPES[base][0]
		for foot in FEET:
			var clip := "%s_%s" % [base, foot]
			assert_bool(library.has_animation(clip)).override_failure_message(clip).is_true()
			var record: Dictionary = records[clip]
			assert_str(record.kind).is_equal("transition")
			assert_bool(record.loop).is_false()
			assert_str(record.joins.first).is_equal(joined)
			assert_str(record.joins.last).is_equal(joined)
			# The angle: the left clip's, the other way for the right one.
			var want: float = TYPES[base][1] * (1.0 if foot == "L" else -1.0)
			var turn: Array = record.turn
			assert_float(turn[0][1]).is_equal_approx(0.0, 0.01)
			(
				assert_float(turn[-1][1])
				. override_failure_message("%s turns %.2f" % [clip, turn[-1][1]])
				. is_equal_approx(want, 0.05)
			)
			# `GaitClips.time_at_turn` reads the curve by its size: it only grows.
			for i in range(1, turn.size()):
				(
					assert_float(absf(turn[i][1]))
					. override_failure_message("%s at frame %d" % [clip, turn[i][0]])
					. is_greater_equal(absf(turn[i - 1][1]) - 0.001)
				)
			# Still on the spot, at the gait's speed for a pivot or a reversal, at both ends.
			var speed: float = 0.0 if joined == "Idle" else records[joined].speed
			for last: bool in [false, true]:
				var got := _speed(record, last)
				(
					assert_float(got)
					. override_failure_message("%s: %.3f m/s" % [clip, got])
					. is_equal_approx(speed, maxf(0.02 * speed, 0.002))
				)
			var free: Array = record.events.filter(
				func(event: Dictionary) -> bool: return event.name == "free"
			)
			assert_int(free.size()).override_failure_message(clip).is_equal(1)


func test_a_turn_meets_its_neighbours_moving_as_they_move() -> void:
	var records := _records()
	_stage(CharacterBodies.FEMALE)
	for base: String in TYPES:
		var joined: String = TYPES[base][0]
		var cycle: Dictionary = records[joined]
		for foot in FEET:
			var clip := "%s_%s" % [base, foot]
			var record: Dictionary = records[clip]
			for last: bool in [false, true]:
				var frame: float = record.joins.get("last_frame" if last else "first_frame", 0.0)
				var mine_a := _places(clip, record.frames - 1.0 if last else 0.0)
				var mine_b := _places(clip, record.frames if last else 1.0)
				var earlier := fposmod(frame - 1.0, cycle.frames) if last else frame
				var theirs_a := _places(joined, earlier)
				var theirs_b := _places(joined, earlier + 1.0)
				var worst := 0.0
				var worst_bone := ""
				for bone: String in mine_a:
					var mine: Vector3 = mine_b[bone] - mine_a[bone]
					var theirs: Vector3 = theirs_b[bone] - theirs_a[bone]
					if mine.distance_to(theirs) > worst:
						worst = mine.distance_to(theirs)
						worst_bone = bone
				var where := (
					"%s %s: %s steps %.1f mm off %s's"
					% [clip, "end" if last else "start", worst_bone, worst * 1e3, joined]
				)
				print(where)
				assert_float(worst).override_failure_message(where).is_less(JOIN_STEP)


func test_the_two_clips_of_a_pair_are_not_mirror_images() -> void:
	var records := _records()
	_stage(CharacterBodies.FEMALE)
	for base: String in TYPES:
		var left: Dictionary = records[base + "_L"]
		var right: Dictionary = records[base + "_R"]
		var frames: float = minf(left.frames, right.frames)
		var worst := 0.0
		for share: float in [0.25, 0.5, 0.75]:
			var one := _places(base + "_L", roundf(share * frames))
			var two := _places(base + "_R", roundf(share * frames))
			for bone: String in one:
				var twin := bone
				if bone.ends_with("_l"):
					twin = bone.trim_suffix("_l") + "_r"
				elif bone.ends_with("_r"):
					twin = bone.trim_suffix("_r") + "_l"
				var mirrored: Vector3 = two[twin] * Vector3(-1.0, 1.0, 1.0)
				worst = maxf(worst, (one[bone] as Vector3).distance_to(mirrored))
		var where := "%s: left and right differ by %.0f mm as mirror images" % [base, worst * 1e3]
		print(where)
		assert_float(worst).override_failure_message(where).is_greater(NOT_A_MIRROR)


# Drives the player through `moves` (`[command, seconds]`), stepping its tree by hand, and returns
# the clips the transitions played and the largest move of any bone between two frames.
func _drive(moves: Array) -> Dictionary:
	var arena: PlayArena = auto_free(PlayArena.new())
	add_child(arena)
	var player := arena.add_player(Vector3.ZERO)
	var animation: CharacterAnimation = player.get_node("Animation")
	var skeleton: Skeleton3D = player.find_children("*", "Skeleton3D", true, false)[0]
	CommandDriver.take(player)
	await get_tree().physics_frame
	await get_tree().physics_frame
	animation.set_throttled(true)
	var played := {}
	var step := CommandDriver.tick_seconds()
	var last_places := {}
	var jump := 0.0
	var where := ""
	for move: Array in moves:
		var command: PlayerCommand = move[0]
		for tick in int(move[1] / step):
			await get_tree().physics_frame
			player.step(command, step)
			animation.advance(step)
			var clip := animation.gait.transitions.clip
			if clip != &"":
				played[String(clip)] = true
			# Bones in the skeleton's space, so the body's own turn and travel are not counted.
			for bone in skeleton.get_bone_count():
				var place := skeleton.get_bone_global_pose(bone).origin
				if last_places.has(bone):
					var moved := place.distance_to(last_places[bone])
					if moved > jump:
						jump = moved
						where = "%s at %s" % [skeleton.get_bone_name(bone), str(played.keys())]
				last_places[bone] = place
	return {"played": played.keys(), "jump": jump, "where": where}


func _command(move: Vector2, sprint := false) -> PlayerCommand:
	var command := PlayerCommand.new()
	command.move = move
	command.sprint = sprint
	return command


func test_the_player_plays_our_reversals_and_pivot() -> void:
	# The tree of gdstudio #1158 picks a reversal by the foot on the side the body turns to and a
	# pivot by the way it turns (`GaitTransitionSet`, `<base>_L` or `_R`); with the shipped
	# settings it finds ours.
	var cases := [
		[[_command(Vector2(0, 1)), 1.2], [_command(Vector2(0, -1)), 1.5]],
		[[_command(Vector2(0, 1), true), 1.5], [_command(Vector2(0, -1), true), 1.8]],
		[[_command(Vector2(0, 1)), 1.2], [_command(Vector2(1, 0)), 1.5]],
	]
	var wanted: Array[String] = ["gds/Jog_Turn_180_", "gds/Sprint_Turn_180_", "gds/Jog_Turn_90_"]
	for index in cases.size():
		var got: Dictionary = await _drive(cases[index])
		var names: Array = got.played
		print(
			"played: ",
			names,
			"; the largest move of a bone in a frame: %.1f mm (%s)" % [got.jump * 1000.0, got.where]
		)
		var found := names.any(func(n: String) -> bool: return n.begins_with(wanted[index]))
		assert_bool(found).override_failure_message("%s in %s" % [wanted[index], names]).is_true()
		# The largest move is printed, not held: the tree still cuts between our clips with no
		# blend (gdstudio #1416, PR #1427, whose test holds every own clip's join to a bound).
