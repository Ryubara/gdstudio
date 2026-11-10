class_name ScreenHost
extends Node
## Opens menu screens over the running game and gives the game back when the last one closes.
## One in the game scene is all a game needs: the pause menu, an inventory, a map are all
## `open(scene)` calls on it.
##
## While any screen is open the host pauses the tree, lets the mouse go (and remembers it was
## captured, to take it again on close) and turns touch-to-mouse on, so a finger can press a
## menu's buttons. When the stack is empty again it puts all three back. The screens live on the
## `UIRouter` stack (`addons/gds_ui`), which runs while the tree is paused.
##
## The host's own input action is `pause` (it does nothing in a game without one); Esc and pad B
## step back through the engine's `ui_cancel`.
##
## To open a screen from gameplay:
## - from code: `ScreenHost.current.open(preload("res://<your screen>.tscn"))`;
## - from a key: add its input action and its scene to `action_screens` in the inspector, and the
##   same key opens and closes it;
## - the screen extends `UIScreen`; give it `back_closes` so Esc and pad B close it.
##
## In a browser the first Esc only lets the pointer lock go and never reaches the game, so the host
## also watches the mouse: when the game had it captured and it is gone, the pause menu opens in
## that same frame. A lost window focus does the same (`pause_on_focus_loss`).

## The first screen opened over the game, and the game paused.
signal opened
## The last screen closed, and the game running again.
signal closed

## The input action that opens the pause menu and closes every screen.
const PAUSE_ACTION := &"pause"

## The host in the tree, for a screen to find (`ScreenHost.current.close()`).
static var current: ScreenHost

@export_group("Screens")
## The menu the `pause` action opens: resume, settings, main menu.
@export var pause_screen: PackedScene
## Screens opened by an input action: the action's name and the scene (for example `inventory`).
## The same action pressed while they are open closes them.
@export var action_screens: Dictionary[StringName, PackedScene] = {}
## How a screen arrives.
@export var transition: UITransition.Kind = UITransition.Kind.FADE

@export_group("Pausing")
## Stops the game's tree while a screen is open. Turn it off for a game that keeps running behind
## its menus (online play); the screens then act as an overlay.
@export var pause_tree := true
## Lets the mouse go while a screen is open, and takes it again afterwards when the game had it.
@export var release_mouse := true
## Opens the pause menu when the game window loses focus.
@export var pause_on_focus_loss := true
## Opens the pause menu when the game had the mouse captured and no longer has it: a browser's
## first Esc, a click outside the page.
@export var pause_on_lost_mouse := true

@export_group("Leaving")
## The scene "Main menu" returns to. Empty returns to the project's main scene (Project Settings,
## Application > Run > Main Scene), and reading it back then gives that scene's path.
@export_file("*.tscn") var menu_scene := "":
	get:
		if menu_scene.is_empty():
			return str(ProjectSettings.get_setting("application/run/main_scene", ""))
		return menu_scene

## Reads the mouse mode instead of `Input.mouse_mode` when valid: a headless run reads the mode
## back as visible whatever was set, so a test stands in a platform under the grip.
var mouse_mode_reader := Callable()
## Takes the mouse mode a screen closing gives back instead of `Input.mouse_mode` when valid.
var mouse_mode_writer := Callable()
## Switches to the menu scene instead of the tree's own change when valid (a `Callable` taking the
## scene's path): a test must not replace the scene the runner stands in.
var scene_changer := Callable()

var _open := false
var _expects_mouse := false
var _held_mouse := false
var _held_touch_mouse := true


func _enter_tree() -> void:
	current = self
	process_mode = Node.PROCESS_MODE_ALWAYS


func _exit_tree() -> void:
	if current == self:
		current = null
	if _open:
		# Leaving with a screen up (the scene is freed, a test ends): the game is not paused for
		# nothing and the router does not keep a menu for a game that is gone.
		_open = false
		get_tree().paused = false
		Input.emulate_mouse_from_touch = _held_touch_mouse
		UIRouter.clear(UITransition.Kind.CUT)


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	UIRouter.screen_changed.connect(_on_screen_changed)


func _process(_delta: float) -> void:
	if _open or not is_inside_tree():
		return
	if _mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		_expects_mouse = true
	elif _expects_mouse:
		# The mouse the game held is gone. `_begin` notes that it was held (to take it again on close)
		# and clears the flag; with the pause off the flag is simply dropped.
		if pause_on_lost_mouse:
			open_pause()
		else:
			_expects_mouse = false


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and pause_on_focus_loss and not _open:
		open_pause()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_echo():
		return
	if InputMap.has_action(PAUSE_ACTION) and event.is_action_pressed(PAUSE_ACTION):
		_toggle(pause_screen, event)
		return
	for action in action_screens:
		if InputMap.has_action(action) and event.is_action_pressed(action):
			_toggle(action_screens[action], event)
			return


## Whether a screen opened by this host is up.
func is_open() -> bool:
	return _open


## Opens the pause menu.
func open_pause() -> void:
	if pause_screen != null:
		open(pause_screen)


## Shows a screen over the game (a `PackedScene`, a path or a `Control`) and pauses it. Opening
## another while one is up stacks it; going back returns to the one below.
func open(source: Variant, kind := -1, params := {}) -> void:
	if not _open:
		_begin()
	UIRouter.push(source, transition if kind < 0 else kind, params)


## Closes every screen and gives the game back.
func close(kind := UITransition.Kind.FADE) -> void:
	if _open:
		UIRouter.clear(kind)


## Leaves the game for the main menu scene (`menu_scene`). With no scene to go to it only warns.
func go_to_menu() -> void:
	var target := menu_scene
	if target.is_empty():
		push_warning(
			"ScreenHost: set `menu_scene` (or the project's main scene) to leave for a menu."
		)
		return
	if _open:
		_end(false)
	_mouse_to(Input.MOUSE_MODE_VISIBLE)
	if scene_changer.is_valid():
		scene_changer.call(target)
	else:
		get_tree().change_scene_to_file(target)


func _toggle(screen: PackedScene, event: InputEvent) -> void:
	if screen == null:
		return
	if not _open:
		open(screen)
		get_viewport().set_input_as_handled()
	elif not InputMap.has_action(&"ui_cancel") or not event.is_action_pressed(&"ui_cancel"):
		# Esc and B step back through the router; any other press of the key closes everything.
		close()
		get_viewport().set_input_as_handled()


func _begin() -> void:
	_open = true
	_held_mouse = _mouse_mode() == Input.MOUSE_MODE_CAPTURED or _expects_mouse
	_expects_mouse = false
	_held_touch_mouse = Input.emulate_mouse_from_touch
	Input.emulate_mouse_from_touch = true
	if release_mouse:
		_mouse_to(Input.MOUSE_MODE_VISIBLE)
	if pause_tree:
		get_tree().paused = true
	opened.emit()


func _end(restore_mouse := true) -> void:
	_open = false
	Input.emulate_mouse_from_touch = _held_touch_mouse
	if pause_tree:
		get_tree().paused = false
	if restore_mouse and release_mouse and _held_mouse:
		# The mouse counts as the game's again only once it is really captured (`_process`): a browser
		# may refuse the lock for a moment, and the menu must not open again for that.
		_mouse_to(Input.MOUSE_MODE_CAPTURED)
	closed.emit()


func _on_screen_changed(depth: int) -> void:
	if depth == 0 and _open:
		_end()


func _mouse_mode() -> Input.MouseMode:
	if mouse_mode_reader.is_valid():
		return mouse_mode_reader.call()
	return Input.mouse_mode


func _mouse_to(mode: Input.MouseMode) -> void:
	if mouse_mode_writer.is_valid():
		mouse_mode_writer.call(mode)
	else:
		Input.mouse_mode = mode
