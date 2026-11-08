@tool
extends EditorPlugin
## Keeps the 3D editor's translate snap equal to the prototype grid's cell size, so a block moved
## with snap on lands on the grid lines the surfaces draw. Both come from one project value: Project
## Settings > Shader Globals > `prototype_cell_size` (metres, 1.0 by default). Change it there and
## the shader's squares and the snap step follow.

const CELL_SETTING := "shader_globals/prototype_cell_size"
const DEFAULT_CELL_M := 1.0
## How many frames the editor gets to build its toolbar before the snap dialog is looked up.
const STARTUP_FRAMES := 3

var _applied_cell := 0.0


func _enter_tree() -> void:
	ProjectSettings.settings_changed.connect(_on_settings_changed)
	_apply_after_startup.call_deferred()


func _exit_tree() -> void:
	if ProjectSettings.settings_changed.is_connected(_on_settings_changed):
		ProjectSettings.settings_changed.disconnect(_on_settings_changed)


## The grid's cell size in metres, from the project's shader global.
static func cell_size() -> float:
	var entry: Variant = ProjectSettings.get_setting(CELL_SETTING, null)
	if entry is Dictionary and entry.has("value"):
		return maxf(float(entry["value"]), 0.01)
	return DEFAULT_CELL_M


## Sets the editor's translate snap step to the cell size. The Snap Settings dialog applies and
## remembers the value when it is confirmed, which is what pressing OK there does.
func apply_snap() -> void:
	var slider := _translate_slider()
	if slider == null:
		return
	var step := cell_size()
	_applied_cell = step
	if not is_equal_approx(slider.value, step):
		slider.value = step
		_confirm_dialog(slider)


## Any project setting may change; the snap follows only a changed cell size, so a step the person
## chose by hand stays.
func _on_settings_changed() -> void:
	if not is_equal_approx(cell_size(), _applied_cell):
		apply_snap()


func _apply_after_startup() -> void:
	for _frame in STARTUP_FRAMES:
		await get_tree().process_frame
	apply_snap()


## The first number box of the 3D editor's Snap Settings dialog is the translate step.
func _translate_slider() -> Control:
	var editors := EditorInterface.get_base_control().find_children(
		"*", "Node3DEditor", true, false
	)
	if editors.is_empty():
		return null
	for dialog in editors[0].get_children():
		if dialog is ConfirmationDialog:
			var sliders := dialog.find_children("*", "EditorSpinSlider", true, false)
			if sliders.size() == 3:
				return sliders[0]
	return null


func _confirm_dialog(slider: Control) -> void:
	var dialog := slider.get_window()
	if dialog is ConfirmationDialog:
		dialog.confirmed.emit()
