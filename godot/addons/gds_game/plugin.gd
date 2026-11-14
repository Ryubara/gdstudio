@tool
extends EditorPlugin
## Adds the export steps of `gds_game` while the plugin is on: a web export serves the GL program
## list beside `index.html` and starts it from the page (`ShaderPrelinkExport`), and its page binds
## skinned meshes' buffers directly on Direct3D 11 (`SkinBuffersExport`), and every export leaves
## the clips nothing names out of the large animation libraries (`ClipExport`).

var _export: ShaderPrelinkExport
var _skin: SkinBuffersExport
var _clips: ClipExport


func _enter_tree() -> void:
	_export = ShaderPrelinkExport.new()
	add_export_plugin(_export)
	_skin = SkinBuffersExport.new()
	add_export_plugin(_skin)
	_clips = ClipExport.new()
	add_export_plugin(_clips)


func _exit_tree() -> void:
	remove_export_plugin(_export)
	remove_export_plugin(_skin)
	remove_export_plugin(_clips)
	_export = null
	_skin = null
	_clips = null
