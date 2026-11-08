extends SceneTree
## Loads every GDScript of the project it runs in; fails when one does not parse.
##
## Started by `gds check scripts`. An import and a short run load only the scripts the
## main scene reaches, so a script that names an autoload the project does not register
## (the `gds_ui` demo without `UIRouter`) stays unseen until the editor or an export
## loads it. This walks `res://`, loads each `.gd` fresh and prints one `PARSE FAIL` line
## per script that does not load (Godot prints the reason) and a total, then exits 1 on
## any failure.
##
## Run: `godot --headless --path <game> -s <this file>`, after an import. It starts in
## `_initialize`, not `_init`: the autoloads join the tree between the two, and a script
## that names one does not compile before they are there.

const SKIPPED := [".godot", ".git", ".import", "reports"]


func _initialize() -> void:
	var scripts: Array[String] = []
	_collect("res://", scripts)
	scripts.sort()
	var failed := 0
	for path in scripts:
		var script := ResourceLoader.load(path, "GDScript", ResourceLoader.CACHE_MODE_REPLACE)
		if script == null or not script is GDScript or not (script as GDScript).can_instantiate():
			failed += 1
			print("PARSE FAIL: ", path)
	print("PARSED: %d script(s), %d failed" % [scripts.size(), failed])
	quit(1 if failed > 0 else 0)


func _collect(folder: String, found: Array[String]) -> void:
	var dir := DirAccess.open(folder)
	if dir == null:
		return
	if dir.file_exists(".gdignore"):
		return
	for sub in dir.get_directories():
		if not SKIPPED.has(sub):
			_collect(folder.path_join(sub), found)
	for file in dir.get_files():
		if file.get_extension() == "gd":
			found.append(folder.path_join(file))
