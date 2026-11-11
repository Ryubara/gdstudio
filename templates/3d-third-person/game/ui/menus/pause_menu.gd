class_name PauseMenu
extends UIScreen
## The pause menu: Resume, Settings, Main menu. Opened by `ScreenHost` over the paused game, so it
## closes the whole stack to resume. Esc and pad B close it too (`back_closes`), and the pad's Start
## (the `pause` action) is handled by the host.

@onready var _resume: Button = %ResumeButton
@onready var _settings: Button = %SettingsButton
@onready var _main_menu: Button = %MainMenuButton


func _ready() -> void:
	super._ready()
	_resume.pressed.connect(_on_resume)
	_settings.pressed.connect(_on_settings)
	_main_menu.pressed.connect(_on_main_menu)
	initial_focus = _resume.get_path()


func _on_resume() -> void:
	if ScreenHost.current != null:
		ScreenHost.current.close()
	else:
		UIRouter.close()


func _on_settings() -> void:
	UIRouter.push("res://ui/menus/settings_menu.tscn", UITransition.Kind.SLIDE)


func _on_main_menu() -> void:
	if ScreenHost.current != null:
		ScreenHost.current.go_to_menu()
