class_name SettingsService
extends Node
## The player's options: loaded from `user://settings.cfg` at start, applied the moment a value
## changes and written back shortly after. It is the autoload `Settings` (the scene
## `settings_service.tscn`), so the main menu, the pause menu and the game read the same values.
##
## Values are plain data keyed `section/name`. Every key has a default and a range, so a missing,
## hand-edited or wrong-typed entry falls back instead of breaking anything. What a value does:
## video, volume and the controls bindings are applied here; mouse sensitivity and invert are read
## by `LookSettings`, which listens to `changed`.
##
## A test run, a capture and an agent's run keep the options in memory (`is_harness_run`), so
## none of them reads or writes the person's own file.

## Emitted after a value changed and was applied.
signal changed(key: StringName, value: Variant)
## Emitted after a binding was changed or the bindings were reset.
signal bindings_changed

enum WindowMode { WINDOWED, FULLSCREEN }

const DEFAULT_PATH := "user://settings.cfg"
## What a harness run gets instead: no file (an empty path loads the defaults and saves nothing).
const HARNESS_PATH := ""
## Set to anything to keep the options in memory in a run the checks below do not recognise.
const HARNESS_ENV := "GDS_NO_USER_FILES"
## The longest saved text accepted, so a damaged file cannot fill memory.
const MAX_TEXT := 4096
const BINDINGS_SECTION := "bindings"

const WINDOW_MODE := &"video/window_mode"
const RESOLUTION_SCALE := &"video/resolution_scale"
const VSYNC := &"video/vsync"
const QUALITY := &"video/quality"
const VOLUME_MASTER := &"audio/master"
const VOLUME_SFX := &"audio/sfx"
const VOLUME_AMBIENT := &"audio/ambient"
const VOLUME_UI := &"audio/ui"
const MOUSE_SENSITIVITY := &"controls/mouse_sensitivity"
const INVERT_Y := &"controls/invert_y"
## Whether the game stops while the inventory is open (read by the inventory screen).
const PAUSE_IN_INVENTORY := &"controls/pause_in_inventory"

## Allowed range of each numeric value.
const RANGES := {
	WINDOW_MODE: Vector2(0, 1),
	RESOLUTION_SCALE: Vector2(50, 100),
	QUALITY: Vector2(0, 2),
	VOLUME_MASTER: Vector2(0, 100),
	VOLUME_SFX: Vector2(0, 100),
	VOLUME_AMBIENT: Vector2(0, 100),
	VOLUME_UI: Vector2(0, 100),
	MOUSE_SENSITIVITY: Vector2(0.2, 3.0),
}

## The audio bus each volume drives (the layout is `res://default_bus_layout.tres`).
const BUSES := {
	VOLUME_MASTER: AudioSettings.MASTER,
	VOLUME_SFX: AudioSettings.SFX,
	VOLUME_AMBIENT: AudioSettings.AMBIENT,
	VOLUME_UI: AudioSettings.UI,
}

@export_group("Saving")
## Seconds after the last change before the file is written (a slider drag is one write).
@export_range(0.0, 5.0, 0.1, "suffix:s") var save_delay := 0.6
@export_group("Video")
## What each quality step sets, lowest first. Edit a preset to change what Low, Medium and High
## mean in this game; the settings screen lists them by `title`.
@export var presets: Array[QualityPreset] = []

## Where the file lives: `default_path()`. A test that wants a file of its own points this at one.
var path := default_path()
## How many times the file was written (a test counts the writes of a visit to a screen).
var write_count := 0
## True in a browser, which owns its window (window mode is not ours to set). Tests inject it.
var is_web := OS.has_feature("web")
## Takes the window mode instead of the real window when it is valid (a Callable taking a
## `DisplayServer.WindowMode`): a test sets one, so no test changes the display it runs on.
var window_setter := Callable()

var _defaults := {}
var _values := {}
## The bindings the player changed: "action.device" to the device's events as data.
var _bindings := {}
## Every action's events as the project declared them, to give back on a reset.
var _declared := {}
var _dirty := false
var _idle := 0.0
## Kept so the browser keeps the page-hide callback alive.
var _page_hide_callback: JavaScriptObject


## The one place that decides where the options are kept: the person's file, unless this is a test
## run (the GdUnit runner), a capture or autopilot (a scene named on the command line: the person
## starts the game from its main scene), a run of the kit's `gds godot` (`GDS_QUIET`) or one that
## asks for it (`HARNESS_ENV`). Those keep them in memory.
static func default_path() -> String:
	return HARNESS_PATH if is_harness_run() else DEFAULT_PATH


static func is_harness_run() -> bool:
	if OS.has_environment(HARNESS_ENV) or OS.get_environment("GDS_QUIET") == "1":
		return true
	for argument in OS.get_cmdline_args():
		if argument.contains("gdUnit4") or argument.ends_with(".tscn"):
			return true
	return false


## The quality step a first run starts at: High on a computer, Medium in a browser or on a phone.
static func default_quality() -> int:
	return 1 if OS.has_feature("web") or OS.has_feature("mobile") else 2


func _init() -> void:
	_defaults = {
		WINDOW_MODE: WindowMode.WINDOWED,
		RESOLUTION_SCALE: 100,
		VSYNC: true,
		QUALITY: default_quality(),
		VOLUME_MASTER: 100,
		VOLUME_SFX: 100,
		VOLUME_AMBIENT: 100,
		VOLUME_UI: 100,
		MOUSE_SENSITIVITY: 1.0,
		INVERT_Y: false,
		PAUSE_IN_INVENTORY: true,
	}
	_values = _defaults.duplicate()
	# A settings screen is opened from the pause menu: the delayed write has to run while the tree is
	# paused, or a change made there is lost with a closed browser tab.
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process(false)


func _ready() -> void:
	# A node with a `_process` has processing switched on when it is ready: nothing is waiting to be
	# written, so off until a change schedules a save.
	set_process(false)
	snapshot_declared_bindings()
	load_from_disk()
	apply_all()
	_flush_when_the_page_hides()


func _process(delta: float) -> void:
	_idle += delta
	if _idle >= save_delay:
		save()


func _notification(what: int) -> void:
	# A browser has no close request: losing focus or hiding the tab is the last chance to write.
	var last_chance := (
		what == NOTIFICATION_WM_CLOSE_REQUEST
		or what == NOTIFICATION_PREDELETE
		or what == NOTIFICATION_APPLICATION_FOCUS_OUT
	)
	if last_chance and _dirty:
		save()


func get_value(key: StringName) -> Variant:
	return _values.get(key, _defaults.get(key))


## The default of a key (what Reset to defaults puts back).
func default_value(key: StringName) -> Variant:
	return _defaults.get(key)


## Sets, applies and schedules a save. An unknown key is ignored; a value of the wrong type or out
## of range is coerced the way loading would.
func set_value(key: StringName, value: Variant) -> void:
	if not _defaults.has(key):
		push_warning("Settings: unknown key '%s'" % key)
		return
	var clean: Variant = _sanitize(key, value)
	if _values[key] == clean:
		return
	_values[key] = clean
	_apply(key)
	_schedule_save()
	changed.emit(key, clean)


## Back to the shipped defaults, bindings included (applied, saved).
func reset_defaults() -> void:
	for key: StringName in _defaults:
		set_value(key, _defaults[key])
	reset_bindings()


## Reads the file. A missing or unreadable file, or a bad entry, leaves the default in place.
func load_from_disk() -> void:
	_values = _defaults.duplicate()
	_bindings.clear()
	if path.is_empty():
		return
	var file := ConfigFile.new()
	if file.load(path) != OK:
		return
	for key: StringName in _defaults:
		var parts := String(key).split("/")
		_values[key] = _sanitize(key, file.get_value(parts[0], parts[1], _defaults[key]))
	if file.has_section(BINDINGS_SECTION):
		for entry in file.get_section_keys(BINDINGS_SECTION):
			var events: Variant = _events_from(file.get_value(BINDINGS_SECTION, entry))
			if _is_binding_key(entry) and events != null:
				_bindings[entry] = file.get_value(BINDINGS_SECTION, entry)


## Writes the file now.
func save() -> Error:
	_dirty = false
	_idle = 0.0
	set_process(false)
	if path.is_empty():
		return OK
	var file := ConfigFile.new()
	for key: StringName in _defaults:
		var parts := String(key).split("/")
		file.set_value(parts[0], parts[1], _values[key])
	for entry: String in _bindings:
		file.set_value(BINDINGS_SECTION, entry, _bindings[entry])
	write_count += 1
	return file.save(path)


## Applies every value and every saved binding; the startup call, and what a test uses to see the
## whole effect.
func apply_all() -> void:
	for key: StringName in _defaults:
		_apply(key)
	_apply_bindings()


## The volume as a linear 0 to 1 factor, for code that mixes by hand.
func volume_linear(key: StringName) -> float:
	return float(get_value(key)) / 100.0


## The preset the quality value picks (the last one when the list is shorter).
func current_preset() -> QualityPreset:
	if presets.is_empty():
		return null
	return presets[clampi(int(get_value(QUALITY)), 0, presets.size() - 1)]


## Remembers every action's events as the project declares them, so a reset can give them back.
func snapshot_declared_bindings() -> void:
	_declared.clear()
	for action in InputMap.get_actions():
		_declared[action] = InputMap.action_get_events(action).duplicate()


## Makes `event` the first binding of `action` for its device (see `InputBindings.rebind`), keeps
## it for the next start, and returns the action that took the binding `action` gave up.
func rebind(action: StringName, event: InputEvent, among: Array[StringName]) -> StringName:
	var swapped := InputBindings.rebind(action, InputBindings.for_map(event), among)
	var device := InputBindings.device_of(event)
	for touched: StringName in [action, swapped]:
		if touched != &"":
			_record_binding(touched, device)
	_schedule_save()
	bindings_changed.emit()
	return swapped


## Gives every action the events the project declared.
func reset_bindings() -> void:
	for action: StringName in _declared:
		if InputMap.has_action(action):
			InputMap.action_erase_events(action)
			for event: InputEvent in _declared[action]:
				InputMap.action_add_event(action, event)
	if not _bindings.is_empty():
		_bindings.clear()
		_schedule_save()
	bindings_changed.emit()


## Whether the player changed an action's binding for a device.
func is_rebound(action: StringName, device: int) -> bool:
	return _bindings.has(_binding_key(action, device))


## On the web, `visibilitychange` (tab hidden, app switched, page closing on mobile) is the one
## event a page reliably gets before it can vanish, so it flushes a pending write.
func _flush_when_the_page_hides() -> void:
	if not OS.has_feature("web"):
		return
	_page_hide_callback = JavaScriptBridge.create_callback(_on_visibility_change)
	JavaScriptBridge.get_interface("document").addEventListener(
		"visibilitychange", _page_hide_callback
	)
	JavaScriptBridge.get_interface("window").addEventListener("pagehide", _page_hide_callback)


func _on_visibility_change(_args: Array) -> void:
	if _dirty:
		save()


func _schedule_save() -> void:
	_dirty = true
	_idle = 0.0
	set_process(true)


func _sanitize(key: StringName, value: Variant) -> Variant:
	var fallback: Variant = _defaults[key]
	match typeof(fallback):
		TYPE_BOOL:
			return value if typeof(value) == TYPE_BOOL else fallback
		TYPE_INT, TYPE_FLOAT:
			return _sanitize_number(key, value, fallback)
	return fallback


func _sanitize_number(key: StringName, value: Variant, fallback: Variant) -> Variant:
	if not _is_finite_number(value):
		return fallback
	var bounds: Vector2 = RANGES.get(key, Vector2(-INF, INF))
	if typeof(fallback) == TYPE_INT:
		return clampi(roundi(float(value)), int(bounds.x), int(bounds.y))
	return clampf(float(value), bounds.x, bounds.y)


## A number a ConfigFile can hold that is neither `nan` nor infinite, which would pass a clamp (nan)
## or become a limit (inf) and be applied as if it were a choice.
func _is_finite_number(value: Variant) -> bool:
	match typeof(value):
		TYPE_INT:
			return true
		TYPE_FLOAT:
			return is_finite(value)
	return false


func _apply(key: StringName) -> void:
	var value: Variant = _values[key]
	match key:
		WINDOW_MODE:
			_apply_window_mode(value)
		RESOLUTION_SCALE:
			if is_inside_tree():
				get_tree().root.scaling_3d_scale = float(value) / 100.0
		VSYNC:
			DisplayServer.window_set_vsync_mode(
				DisplayServer.VSYNC_ENABLED if value else DisplayServer.VSYNC_DISABLED
			)
		QUALITY:
			_apply_preset(current_preset())
		_:
			if BUSES.has(key):
				AudioSettings.set_player_gain(BUSES[key], float(value) / 100.0)


func _apply_window_mode(mode: int) -> void:
	# A browser owns its window: the page decides, so there is nothing to set.
	if is_web:
		return
	var target := (
		DisplayServer.WINDOW_MODE_FULLSCREEN
		if mode == WindowMode.FULLSCREEN
		else DisplayServer.WINDOW_MODE_WINDOWED
	)
	if window_setter.is_valid():
		window_setter.call(target)
	else:
		DisplayServer.window_set_mode(target)


func _apply_preset(preset: QualityPreset) -> void:
	if preset == null:
		return
	if is_inside_tree():
		get_tree().root.msaa_3d = preset.msaa
	RenderingServer.directional_shadow_atlas_set_size(preset.shadow_atlas_size, true)
	RenderingServer.directional_soft_shadow_filter_set_quality(preset.shadow_filter)
	RenderingServer.positional_soft_shadow_filter_set_quality(preset.shadow_filter)


func _apply_bindings() -> void:
	for entry: String in _bindings:
		var events: Variant = _events_from(_bindings[entry])
		var parts := entry.rsplit(".", true, 1)
		if events == null or not InputMap.has_action(parts[0]):
			continue
		InputBindings.set_events(StringName(parts[0]), _device_from(parts[1]), events)


func _record_binding(action: StringName, device: int) -> void:
	var data: Array = []
	for event in InputBindings.events_of(action, device):
		data.append(InputBindings.to_data(event))
	_bindings[_binding_key(action, device)] = data


static func _binding_key(action: StringName, device: int) -> String:
	return "%s.%s" % [action, "pad" if device == InputBindings.Device.GAMEPAD else "keys"]


static func _device_from(word: String) -> int:
	return InputBindings.Device.GAMEPAD if word == "pad" else InputBindings.Device.KEYBOARD


static func _is_binding_key(entry: String) -> bool:
	return entry.ends_with(".pad") or entry.ends_with(".keys")


## The events a saved list holds, or null when it is not a list of valid ones (an empty list is a
## valid one: the player unbound the control).
func _events_from(data: Variant) -> Variant:
	if not data is Array or (data as Array).size() > 8:
		return null
	var events: Array[InputEvent] = []
	for item in data:
		var event := InputBindings.event_from_data(item)
		if event == null:
			return null
		events.append(event)
	return events
