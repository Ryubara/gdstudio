class_name OnlineStatus
extends CanvasLayer
## What an online game shows while it is not simply playing: "Loading" while the client waits for
## the level's warm-up before it joins (`NetClient.is_waiting_to_join`), "Connecting" until the
## server seats the player, then nothing; a message and a way back when the server refuses the
## player (it runs another version: reload; the game is full; it was built from another map), when
## nothing answers within `connect_seconds`, and when a seated game's connection is lost. Its
## `client`'s signals drive it; it sends nothing. While a message shows, the game is dimmed behind
## it, the player's input is off and the mouse free.
##
## The texts are exports: open the scene to reword or restyle them.

## Said when the shown state changes.
signal state_changed(state: State)

enum State {
	CONNECTING, PLAYING, OLD_VERSION, FULL, OTHER_MAP, UNREACHABLE, LOST, NO_ADDRESS, LOADING
}

## The scene "Back to menu" goes to.
@export_file("*.tscn") var menu_scene := "res://ui/menus/menu_scene.tscn"
## Seconds the link may take to open and seat the player before it counts as unreachable. Only
## frames shorter than `StallGuard.STALL_SECONDS` count: a page that spends its first seconds
## compiling shaders has not waited for the server, and the wait for the warm-up (Loading) is not
## counted at all.
@export_range(1.0, 60.0, 0.5, "suffix:s") var connect_seconds := 10.0

@export_group("Texts")
## Shown while the client waits for the level to be ready before it joins.
@export var loading_text := "Loading"
@export var connecting_text := "Connecting"
@export_multiline var old_version_text := "The server runs another version of the game."
## The way out of `old_version_text`: a page reloads to get the server's version.
@export var reload_hint_web := "Reload the page to get it."
@export var reload_hint_desktop := "Update the game to join."
@export_multiline var full_text := "The game is full."
@export_multiline var other_map_text := "The server runs another map."
@export_multiline var unreachable_text := "The server did not answer."
@export_multiline var lost_text := "Connection lost."
@export_multiline var no_address_text := "No server address."

@export_group("Nodes")
## The client whose state is shown.
@export var client: NetClient

## The state shown.
var state := State.CONNECTING
## Seconds since the scene started, while connecting.
var waited := 0.0

@onready var _root: Control = %Root
@onready var _title: Label = %Title
@onready var _message: Label = %Message
@onready var _back: Button = %BackButton
@onready var _reload: Button = %ReloadButton


func _ready() -> void:
	_back.pressed.connect(back_to_menu)
	_reload.pressed.connect(_on_reload)
	if client != null:
		client.welcomed.connect(_on_welcomed)
		client.refused.connect(_on_refused)
		client.disconnected.connect(_on_disconnected)
	var loading := client != null and client.is_waiting_to_join()
	_show(State.LOADING if loading else State.CONNECTING)


func _process(delta: float) -> void:
	if state == State.LOADING:
		if not client.is_waiting_to_join():
			_show(State.CONNECTING)
		return
	if state != State.CONNECTING:
		return
	if delta < StallGuard.STALL_SECONDS:
		waited += delta
	if client == null or client.link == null:
		_show(State.NO_ADDRESS)
	elif waited >= connect_seconds:
		_show(State.UNREACHABLE)
		client.link.close()


## The text shown for `shown` (empty while playing).
func text_of(shown: State) -> String:
	var hint := reload_hint_web if OS.has_feature("web") else reload_hint_desktop
	var texts := {
		State.LOADING: loading_text,
		State.CONNECTING: connecting_text,
		State.OLD_VERSION: "%s %s" % [old_version_text, hint],
		State.FULL: full_text,
		State.OTHER_MAP: other_map_text,
		State.UNREACHABLE: unreachable_text,
		State.LOST: lost_text,
		State.NO_ADDRESS: no_address_text,
	}
	return texts.get(shown, "")


## The message shown now (empty while playing).
func message() -> String:
	return text_of(state)


## Leaves the online game for the main menu.
func back_to_menu() -> void:
	if client != null and client.link != null:
		client.link.close()
	get_tree().change_scene_to_file.call_deferred(menu_scene)


func _show(shown: State) -> void:
	state = shown
	var playing := shown == State.PLAYING
	# The dimmed screen behind the panel also keeps a click off the game (the camera's capture).
	_root.visible = not playing
	var waiting := shown == State.CONNECTING or shown == State.LOADING
	_title.text = text_of(shown) if waiting else ""
	_title.visible = waiting
	_message.text = "" if waiting else text_of(shown)
	_message.visible = not _message.text.is_empty()
	_back.visible = not playing
	_reload.visible = shown == State.OLD_VERSION and OS.has_feature("web")
	if client != null and client.player != null:
		client.player.input_enabled = playing
	if not playing:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		(_reload if _reload.visible else _back).grab_focus.call_deferred()
	state_changed.emit(shown)


func _on_welcomed(_slot: int) -> void:
	_show(State.PLAYING)


func _on_refused(reason: int) -> void:
	match reason:
		NetWire.Refusal.VERSION:
			_show(State.OLD_VERSION)
		NetWire.Refusal.FULL:
			_show(State.FULL)
		NetWire.Refusal.WORLD:
			_show(State.OTHER_MAP)


func _on_disconnected() -> void:
	match state:
		State.PLAYING:
			_show(State.LOST)
		State.CONNECTING:
			_show(State.UNREACHABLE)


func _on_reload() -> void:
	if OS.has_feature("web"):
		JavaScriptBridge.eval("window.location.reload()")
