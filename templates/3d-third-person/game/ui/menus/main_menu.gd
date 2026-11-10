class_name MainMenu
extends UIScreen
## The main menu: Play, Settings, Quit (Quit is left out in a browser, which has no program to
## leave). Play shows the loading screen, which loads the game scene and switches to it.

## The scene Play loads.
@export_file("*.tscn") var game_scene := "res://main.tscn"
## The title shown; empty uses the project's name.
@export var title := ""

@onready var _title: Label = %Title
@onready var _play: Button = %PlayButton
@onready var _settings: Button = %SettingsButton
@onready var _quit: Button = %QuitButton


func _ready() -> void:
	super._ready()
	_title.text = (
		title if title != "" else str(ProjectSettings.get_setting("application/config/name"))
	)
	_play.pressed.connect(play)
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


## Wraps the focus round the column, so Up on Play reaches the last button and Down on the last
## reaches Play: no key or pad press ends on a button with nothing beyond it.
func _link_focus() -> void:
	var buttons: Array[Control] = []
	for button in [_play, _settings, _quit]:
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
