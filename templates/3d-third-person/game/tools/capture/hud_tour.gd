## Films the HUD: the crosshair, the coin counter, and the health and ammo parts fed by a stand-in
## (the real player has neither yet), while the character picks up coins, aims and takes damage.
## With the user argument `phone` it brings the touch controls up and sets the page's pixel ratio
## to 2, so a window of 1688 x 780 stands for an 844 x 390 phone page.
##
## Record it with Movie Maker through the kit, in the window size you want:
## `gds godot -- --path game --scene res://tools/capture/hud_tour.tscn --write-movie out.png
##  --fixed-fps 10 --quit-after 80 --resolution 1688x780 -- phone`
## It lives in tools/, which the export leaves out, and nothing in the game refers to it.
extends Node

var _frame := 0
var _subject: HudSubject
var _weapon: HudSubjectWeapon

@onready var _hud: Hud = $Main/Hud
@onready var _player: Player = $Main/Player


func _ready() -> void:
	if OS.get_cmdline_user_args().has("phone"):
		_hud.pixel_ratio = 2.0
		var touch: TouchControls = $Main/TouchControls
		touch.show_mode = TouchControls.ShowMode.ALWAYS
		touch._set_shown(true)
	_subject = HudSubject.new()
	_weapon = HudSubjectWeapon.new()
	_subject.add_child(_weapon)
	_subject.weapon = _weapon
	add_child(_subject)


func _physics_process(_delta: float) -> void:
	_frame += 1
	match _frame:
		5:
			_player.collect(&"coin", 3)
		10:
			for widget in _hud.widgets():
				if widget is HudStat:
					widget.player = _subject
			_subject.set_health(100.0)
			_weapon.set_ammo(12)
		30:
			Input.action_press(&"aim")
		45:
			_player.collect(&"coin", 9)
			_player.collect(&"gem", 1)
			_subject.set_health(45.0)
			_weapon.set_ammo(7)
		60:
			_subject.set_health(18.0)
			_weapon.set_ammo(2)
