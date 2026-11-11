@tool
extends EditorPlugin
## Adds the export step of `gds_game` while the plugin is on: a web export serves the GL program
## list beside `index.html` and starts it from the page (`ShaderPrelinkExport`).

var _export: ShaderPrelinkExport


func _enter_tree() -> void:
	_export = ShaderPrelinkExport.new()
	add_export_plugin(_export)


func _exit_tree() -> void:
	remove_export_plugin(_export)
	_export = null
