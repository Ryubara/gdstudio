extends SceneTree
## Starts the AI soak (`tools/soak/ai_soak.tscn`) after making `--objects N` objects (default 1)
## that it keeps for the whole run: a run whose AI took a phase, a seed or an order from an
## instance id takes another course than the plain soak's. Its other options after `--` are the
## soak's own. Run as a main loop of its own, from the game folder:
## `godot --headless --path . --fixed-fps 60 -s <this script> -- --seed 11 --objects 1`
##
## The soak goes into the tree here, before the engine's first frame, as a scene named on the
## command line does: added a frame later (`change_scene_to_file`), the same soak steps its
## physics apart in the last bit (the first ragdoll after four ticks, kit #1591) and the hash
## differs with no object made at all.

const SOAK := "res://tools/soak/ai_soak.tscn"

var _kept: Array[RefCounted] = []


func _initialize() -> void:
	var count := 1
	var args := OS.get_cmdline_user_args()
	var at := args.find("--objects")
	if at >= 0 and at + 1 < args.size():
		count = int(args[at + 1])
	for index in count:
		_kept.append(RefCounted.new())
	var soak: Node = (load(SOAK) as PackedScene).instantiate()
	root.add_child(soak)
	current_scene = soak
