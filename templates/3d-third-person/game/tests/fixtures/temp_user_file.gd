class_name TempUserFile
extends RefCounted
## A `user://` file name of a suite's own, for this run alone. Every run of the game shares one
## `user://` folder (every game `gds template test` makes has the same name), so with a fixed name
## two runs at the same time write, read and delete each other's file; the process id keeps them
## apart.


## The path for `stem` in this run: `user://<stem>_<process id>.cfg`.
static func path(stem: String) -> String:
	return "user://%s_%d.cfg" % [stem, OS.get_process_id()]


## Deletes the file at `file_path` if it is there: before a test, a crashed run's leftover; after
## it, its own.
static func remove(file_path: String) -> void:
	if FileAccess.file_exists(file_path):
		DirAccess.remove_absolute(file_path)
