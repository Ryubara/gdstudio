extends SceneTree
## Loads the resources named after `--` in that order and quits, for a test that reads what Godot
## prints at exit (`tests/gameplay/test_load_order_leaks.gd`). It names no class, so a folder scan
## that compiles it loads nothing else.


func _init() -> void:
	for path in OS.get_cmdline_user_args():
		var loaded := load(path)
		if loaded == null:
			printerr("LOAD_ORDER_PROBE could not load %s" % path)
	print("LOAD_ORDER_PROBE done")
	quit()
