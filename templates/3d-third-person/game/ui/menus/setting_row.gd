@tool
class_name SettingRow
extends UIRow
## A row of the settings screen bound to one key of the `Settings` autoload. Put a `UISlider`,
## `UIToggle` or `UIOptionSelector` under it (the row moves it into its control column when the
## game starts) and set `key`: the control shows the saved value, and a change goes to `Settings`,
## which applies it at once and saves it.
##
## Nothing here knows which settings exist: a game adds a row to its settings scene and gives it a
## key from `SettingsService`.

## The settings key this row shows and changes, for example `video/vsync`.
@export var key: StringName = &""
## How a slider's number is written beside it (`%d%%`, `%.2fx`).
@export var format := "%d%%"
## What each option of an option selector means, in order. Empty means 0, 1, 2 and so on.
@export var option_values := PackedFloat32Array()
## Fills an option selector with the quality presets' titles instead of its own list.
@export var options_from_presets := false
## Leaves the row out in a browser, which decides this setting itself (window mode, vsync).
@export var hide_on_web := false

var _shown_once := false


func _ready() -> void:
	super._ready()
	if Engine.is_editor_hint():
		return
	if hide_on_web and OS.has_feature("web"):
		hide()
		return
	for child in get_children():
		if child is UISlider or child is UIToggle or child is UIOptionSelector:
			remove_child(child)
			set_control(child)
			break
	if control == null:
		push_warning("SettingRow '%s' has no UISlider, UIToggle or UIOptionSelector child." % name)
		return
	if options_from_presets and control is UIOptionSelector:
		_fill_from_presets()
	_connect_control()
	var settings := _settings()
	if settings != null:
		settings.changed.connect(_on_setting_changed)
	refresh()


## Puts the control at the saved value without sending a change back.
func refresh() -> void:
	var settings := _settings()
	if settings == null or control == null or key == &"":
		return
	var value: Variant = settings.get_value(key)
	if control is UISlider:
		(control as UISlider).set_value_no_signal(float(value))
		set_value_text(format % float(value))
	elif control is UIToggle:
		(control as UIToggle).set_pressed_no_signal(bool(value))
	elif control is UIOptionSelector:
		var selector := control as UIOptionSelector
		# The first time the row shows the value it is set, not slid to.
		if _shown_once:
			selector.select(_index_of(float(value)), false)
		else:
			selector.jump_to(_index_of(float(value)))
	_shown_once = true


func _connect_control() -> void:
	if control is UISlider:
		(control as UISlider).value_changed.connect(_on_slider_changed)
	elif control is UIToggle:
		(control as UIToggle).toggled.connect(_on_toggled)
	elif control is UIOptionSelector:
		(control as UIOptionSelector).selected_changed.connect(_on_option_changed)


func _on_slider_changed(value: float) -> void:
	set_value_text(format % value)
	_send(value)


func _on_toggled(on: bool) -> void:
	_send(on)


func _on_option_changed(index: int) -> void:
	_send(option_values[index] if index < option_values.size() else index)


func _send(value: Variant) -> void:
	var settings := _settings()
	if settings != null:
		settings.set_value(key, value)


func _on_setting_changed(changed_key: StringName, _value: Variant) -> void:
	if changed_key == key:
		refresh()


func _fill_from_presets() -> void:
	var settings := _settings()
	if settings == null:
		return
	var titles := PackedStringArray()
	for preset in settings.presets:
		titles.append(preset.title)
	(control as UIOptionSelector).options = titles


## The option nearest to a value, so a hand-edited value between two choices shows the closer one.
func _index_of(value: float) -> int:
	var selector := control as UIOptionSelector
	var best := 0
	var best_gap := INF
	for i in selector.options.size():
		var option_value := option_values[i] if i < option_values.size() else float(i)
		if absf(option_value - value) < best_gap:
			best_gap = absf(option_value - value)
			best = i
	return best


func _settings() -> SettingsService:
	return get_node_or_null("/root/Settings") as SettingsService
