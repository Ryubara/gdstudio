## The rifle's two reloads in the running game (kit #1402): `main.tscn` with the rifle given to the
## player, drawn, and reloaded a second in from a magazine of `RELOAD_ROUNDS` rounds (0, the
## default: an empty reload, which ends with the charging handle's pull; 3: a tactical reload,
## which has none and leaves the bolt home). Recorded by Movie Maker frame by frame from the game's
## own camera (`RELOAD_VIEW=game`, the default) or from a close-up camera where the aim camera is,
## behind the right shoulder, zoomed on the rifle (`RELOAD_VIEW=close`); `RELOAD_MODEL=male` puts
## the male body on the player. It prints a `RELOAD` line a frame (the reload's share, the bolt's
## travel back in millimetres, the rounds).
##
## `gds capture frames --project game --scene res://tools/capture/rifle_reload_live.tscn
## --seconds 3.6 --fps 30`. It lives in tools/, which the export leaves out.
extends Node3D

const RIFLE := "res://gameplay/weapon/rifle.tres"
## Seconds from the start to the reload, for the rifle to be drawn and the game to settle.
const START := 1.0
## Where the close-up camera is, in the character's space (+Z its front): behind and to the right
## of the rifle as the aim camera is, a little higher; its field of view.
const CLOSE := Vector3(-0.45, 1.75, -0.95)
const CLOSE_FOV := 24.0

var _player: Player
var _camera: Camera3D
var _age := 0.0
var _reloaded := false


func _ready() -> void:
	var main := (load("res://main.tscn") as PackedScene).instantiate()
	add_child(main)
	_player = main.get_node("PlayerRig/Player") as Player
	if OS.get_environment("RELOAD_MODEL") == "male":
		var slot := _player.model
		var old := slot.rig()
		slot.remove_child(old)
		old.free()
		slot.add_child((load(CharacterBodies.MALE) as PackedScene).instantiate())
	_player.loadout.give.call_deferred(load(RIFLE) as WeaponDef, 60)
	if OS.get_environment("RELOAD_VIEW") == "close":
		_camera = Camera3D.new()
		_camera.fov = CLOSE_FOV
		_camera.near = 0.02
		add_child(_camera)
		_camera.make_current()


func _process(delta: float) -> void:
	_age += delta
	var rounds := (
		int(OS.get_environment("RELOAD_ROUNDS")) if OS.has_environment("RELOAD_ROUNDS") else 0
	)
	if not _reloaded and _age >= START:
		_reloaded = true
		_player.weapon.set_ammo(rounds, 60)
		_player.weapon.reload()
	var hold := _player.model.get_node_or_null("RifleHeld") as TwoHandHold
	if hold == null:
		return
	var rifle := hold.get_node(^"Pivot/Rifle") as Node3D
	if _camera != null:
		_camera.global_position = _player.model.global_transform * CLOSE
		_camera.look_at(rifle.global_position, Vector3.UP)
	var bolt := hold.get_node_or_null(hold.bolt) as Node3D
	var reload := _player.weapon.reload_progress() if _player.weapon.is_reloading() else -1.0
	print(
		(
			"RELOAD %.3f share %.3f bolt %s ammo %s"
			% [_age, reload, bolt.position if bolt != null else Vector3.ZERO, _player.weapon.ammo]
		)
	)
