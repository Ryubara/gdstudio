# The senses' contract: every export of `AiSenses`, `AiSensesView`, `AiNoise` and `AiNoiseMaker`
# with its default (the kit's `docs/engines/godot/third-person/ai-senses.md#inspector` lists the
# same), the board in the world and the noise maker on the body a server loads, and the brain's
# firewall (Deadnight's): no script of `gameplay/ai/` outside the perception and plumbing layer
# names the world nodes or queries the space; the brain reads beliefs.
extends GdUnitTestSuite

const AI_FOLDER := "res://gameplay/ai"
## The layer that may read the world: perception, relationships, the path and steering, the
## director that measures the tiers, the body's animation throttle, the spawner that places
## characters in the level (it waits for a player and hands an ally its leader).
const MAY_READ_THE_WORLD: Array[String] = [
	"res://gameplay/ai/senses/",
	"res://gameplay/ai/relations/",
	"res://gameplay/ai/navigation/",
	"res://gameplay/ai/ai_director.gd",
	"res://gameplay/ai/ai_animation_throttle.gd",
	"res://gameplay/ai/spawner/",
]
## What a brain script must not name: the tree's groups, the physics space, the player.
const FORBIDDEN: Array[String] = [
	"get_nodes_in_group",
	"get_first_node_in_group",
	"direct_space_state",
	"intersect_ray",
	"intersect_shape",
	"PhysicsRayQueryParameters3D",
	"Player.",
	'&"player"',
]


func test_the_senses_defaults_are_pinned() -> void:
	var senses: AiSenses = auto_free(AiSenses.new())
	var pins := {
		&"sight": true,
		&"hearing": true,
		&"touch": true,
		&"team": true,
		&"target_groups": [&"player", &"ai_characters"],
		&"care_up_to": AiRelations.Band.UNFRIENDLY,
		&"startled_by": [],
		&"sight_mask": PhysicsLayers.CAMERA_MASK,
		&"eye": null,
		&"target_height_share": 0.85,
		&"far_share": 0.3,
		&"side_share": 0.5,
		&"still_share": 0.7,
		&"crouch_share": 0.6,
		&"prone_share": 0.35,
		&"unfriendly_share": 0.5,
		&"glimpse_seconds": 3.0,
		&"heard_gain": 0.5,
		&"ray_fresh_seconds": 0.3,
		&"authority_only": true,
		&"show_view": false,
		&"view": null,
	}
	assert_array(ExportPins.differences(senses, pins)).is_empty()
	assert_array(ExportPins.wrong_values(senses, pins)).is_empty()


func test_the_noise_board_and_maker_defaults_are_pinned() -> void:
	var board: AiNoise = auto_free(AiNoise.new())
	var board_pins := {
		&"radii":
		{
			AiNoise.FOOTSTEP: 9.0,
			AiNoise.LANDING: 12.0,
			AiNoise.SHOT: 45.0,
			AiNoise.IMPACT: 14.0,
			AiNoise.EXPLOSION: 70.0,
		},
		&"default_radius": 10.0,
		&"occlusion": 0.5,
		&"reference_hearing": 30.0,
		&"keep_seconds": 1.0,
		&"capacity": 128,
		&"show_noises": false,
	}
	assert_array(ExportPins.differences(board, board_pins)).is_empty()
	assert_array(ExportPins.wrong_values(board, board_pins)).is_empty()
	var maker: AiNoiseMaker = auto_free(AiNoiseMaker.new())
	var maker_pins := {
		&"enabled": true,
		&"stride": 1.4,
		&"loud_speed": 4.5,
		&"max_loudness": 1.4,
		&"min_loudness": 0.15,
		&"crouch_share": 0.4,
		&"prone_share": 0.2,
		&"check_ticks": 6,
		&"shot_loudness": 1.0,
		&"impact_loudness": 1.0,
		&"loud_landing": 8.0,
	}
	assert_array(ExportPins.differences(maker, maker_pins)).is_empty()
	assert_array(ExportPins.wrong_values(maker, maker_pins)).is_empty()


func test_the_view_defaults_are_pinned() -> void:
	var view: AiSensesView = auto_free(AiSensesView.new())
	var pins := {
		&"cone_color": Color(1.0, 0.85, 0.2, 0.16),
		&"edge_color": Color(1.0, 0.85, 0.2, 0.9),
		&"near_color": Color(1.0, 0.45, 0.2, 0.9),
		&"hearing_color": Color(0.4, 0.7, 1.0, 0.45),
		&"seen_color": Color(0.3, 1.0, 0.35, 0.95),
		&"memory_color": Color(1.0, 0.7, 0.15, 0.95),
		&"heard_color": Color(0.4, 0.7, 1.0, 0.95),
		&"bar_back_color": Color(0.0, 0.0, 0.0, 0.55),
		&"bar_height": 2.45,
		&"bar_thickness": 0.09,
		&"bar_length": 0.9,
		&"line_width": 0.04,
		&"segments": 32,
	}
	assert_array(ExportPins.differences(view, pins)).is_empty()


func test_the_world_holds_the_board_and_the_body_makes_noises() -> void:
	var world := (load("res://world/world.tscn") as PackedScene).instantiate()
	assert_object(world.get_node_or_null("AiNoise") as AiNoise).is_not_null()
	world.free()
	var body := (load("res://gameplay/character/character.tscn") as PackedScene).instantiate()
	assert_object(body.get_node_or_null("NoiseMaker") as AiNoiseMaker).is_not_null()
	body.free()


func test_the_brain_reads_beliefs_never_the_world() -> void:
	var scanned := 0
	var offences: Array[String] = []
	for path in _scripts_under(AI_FOLDER):
		if MAY_READ_THE_WORLD.any(func(allowed: String) -> bool: return path.begins_with(allowed)):
			continue
		scanned += 1
		var text := FileAccess.get_file_as_string(path)
		for line_number in text.count("\n") + 1:
			var line := text.get_slice("\n", line_number)
			if line.strip_edges().begins_with("#"):
				continue
			for word in FORBIDDEN:
				if line.contains(word):
					offences.append("%s:%d names %s" % [path, line_number + 1, word])
	assert_int(scanned).is_greater_equal(5)
	assert_array(offences).is_empty()


func test_the_firewall_catches_a_brain_that_reads_the_world() -> void:
	var line := '\tvar target := get_tree().get_first_node_in_group(&"player")'
	var caught := FORBIDDEN.filter(func(word: String) -> bool: return line.contains(word))
	assert_int(caught.size()).is_equal(2)


func _scripts_under(folder: String) -> Array[String]:
	var found: Array[String] = []
	var directory := DirAccess.open(folder)
	if directory == null:
		return found
	for file in directory.get_files():
		if file.ends_with(".gd"):
			found.append(folder.path_join(file))
	for sub in directory.get_directories():
		found.append_array(_scripts_under(folder.path_join(sub)))
	return found
