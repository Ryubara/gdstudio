# Orders of loading that once left the game's scripts in use at exit (kit #1554). Each order runs
# in a headless Godot of its own (`tests/fixtures/load_order_probe.gd`), which loads the paths and
# quits; the test fails on Godot's leak lines, the ones CI's shard gate greps for.
#
# The minimap marker (it names `MinimapHeading` and `MinimapSection`), then the character, then a
# scene with a `Hotbar` whose `start_items` hold the bandage (its drop scene holds a marker): with
# `start_items` exported as `Array[ItemDef]` this left 280 objects, 179 scripts and the vault
# probe's shapes alive. A shard that ran `test_minimap_heading.gd` before any suite that made a
# `NetServer` (it preloads `body_items.tscn`) failed with every case green.
extends GdUnitTestSuite

const PROBE := "res://tests/fixtures/load_order_probe.gd"
const LEAK_LINES := ["leaked at exit", "still in use"]
const ORDERS := [
	[
		"res://core/minimap/minimap_marker.gd",
		"res://gameplay/character/character.gd",
		"res://gameplay/net/body_items.tscn",
	],
	["res://core/minimap/minimap_marker.gd", "res://gameplay/net/net_server.gd"],
]


func test_no_order_leaves_scripts_in_use_at_exit() -> void:
	for order: Array in ORDERS:
		var printed := _probe(PackedStringArray(order))
		assert_str(printed).contains("LOAD_ORDER_PROBE done")
		for line in printed.split("\n"):
			for leak: String in LEAK_LINES:
				(
					assert_bool(line.contains(leak))
					. override_failure_message("%s\nleft: %s" % [" then ".join(order), line])
					. is_false()
				)


# What a headless Godot prints while it loads `paths` in order and quits.
func _probe(paths: PackedStringArray) -> String:
	var output: Array = []
	var args := PackedStringArray(
		["--headless", "--path", ProjectSettings.globalize_path("res://"), "-s", PROBE, "--"]
	)
	args.append_array(paths)
	OS.execute(OS.get_executable_path(), args, output, true)
	return "\n".join(PackedStringArray(output))
