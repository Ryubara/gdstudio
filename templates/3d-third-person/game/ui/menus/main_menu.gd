class_name MainMenu
extends UIScreen
## The main menu: Play, Play online, Settings, Quit (Quit is left out in a browser, which has no
## program to leave). Play shows the loading screen, which loads the game scene and switches to it;
## Play online does the same with the online game, which joins `server_address`. The address field
## under it is a developer's: it shows in a debug build (the editor, a debug export) and never in a
## release, where the game's own `server_address` is the only one a player meets.

## When the address field shows.
enum AddressField { DEBUG_BUILDS, ALWAYS, NEVER }

## The scene Play loads.
@export_file("*.tscn") var game_scene := "res://main.tscn"
## The scene Play online loads; empty hides the button.
@export_file("*.tscn") var online_scene := "res://online_main.tscn"
## The server Play online joins (`ws://` or `wss://`; a page served over `https` may open only
## `wss://`).
@export var server_address := "ws://127.0.0.1:8910"
## When the address field shows (a developer setting).
@export var address_field := AddressField.DEBUG_BUILDS
## The title shown; empty uses the project's name.
@export var title := ""

@onready var _title: Label = %Title
@onready var _play: Button = %PlayButton
@onready var _online: Button = %OnlineButton
@onready var _address: LineEdit = %AddressField
@onready var _settings: Button = %SettingsButton
@onready var _quit: Button = %QuitButton


func _ready() -> void:
	super._ready()
	_title.text = (
		title if title != "" else str(ProjectSettings.get_setting("application/config/name"))
	)
	_play.pressed.connect(play)
	_online.pressed.connect(play_online)
	_online.visible = not online_scene.is_empty()
	_address.text = server_address
	_address.visible = _online.visible and shows_address()
	_address.text_submitted.connect(func(_text: String) -> void: play_online())
	_settings.pressed.connect(_on_settings)
	_quit.pressed.connect(_on_quit)
	_quit.visible = not OS.has_feature("web")
	initial_focus = _play.get_path()
	_link_focus()


## Starts the game: the loading screen takes over and switches to `game_scene` when it is read.
func play() -> void:
	UIRouter.replace(
		"res://ui/menus/loading_screen.tscn", UITransition.Kind.FADE, {"scene": game_scene}
	)


## Starts the online game: the loading screen switches to `online_scene`, whose client joins the
## address in the field (or `server_address`).
func play_online() -> void:
	var address := _address.text.strip_edges() if _address.visible else server_address
	NetClient.next_url = address if not address.is_empty() else server_address
	UIRouter.replace(
		"res://ui/menus/loading_screen.tscn", UITransition.Kind.FADE, {"scene": online_scene}
	)


## Whether the address field shows in this build.
func shows_address() -> bool:
	match address_field:
		AddressField.ALWAYS:
			return true
		AddressField.NEVER:
			return false
	return OS.is_debug_build()


## Wraps the focus round the column, so Up on Play reaches the last button and Down on the last
## reaches Play: no key or pad press ends on a button with nothing beyond it.
func _link_focus() -> void:
	var buttons: Array[Control] = []
	for button in [_play, _online, _address, _settings, _quit]:
		if button.visible:
			buttons.append(button)
	for i in buttons.size():
		var up := buttons[(i - 1 + buttons.size()) % buttons.size()]
		var down := buttons[(i + 1) % buttons.size()]
		buttons[i].focus_neighbor_top = buttons[i].get_path_to(up)
		buttons[i].focus_neighbor_bottom = buttons[i].get_path_to(down)


func _on_settings() -> void:
	UIRouter.push("res://ui/menus/settings_menu.tscn", UITransition.Kind.SLIDE)


func _on_quit() -> void:
	get_tree().quit()
