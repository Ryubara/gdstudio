@tool
extends EditorPlugin
## Adds the export steps of `gds_game` while the plugin is on: a web export serves the GL program
## list beside `index.html` and starts it from the page (`ShaderPrelinkExport`), and its page binds
## skinned meshes' buffers directly on Direct3D 11 (`SkinBuffersExport`).

var _export: ShaderPrelinkExport
var _skin: SkinBuffersExport


func _enter_tree() -> void:
	_export = ShaderPrelinkExport.new()
	add_export_plugin(_export)
	_skin = SkinBuffersExport.new()
	add_export_plugin(_skin)


func _exit_tree() -> void:
	remove_export_plugin(_export)
	remove_export_plugin(_skin)
	_export = null
	_skin = null
