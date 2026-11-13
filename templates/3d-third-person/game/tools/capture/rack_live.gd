## The slide's rack in the running game (kit #1337): `main.tscn` with the player's pistol emptied
## and reloaded half a second in, so the reload ends with the rack (`RackLayer`, `WeaponHold`).
## Recorded by Movie Maker frame by frame from the game's own camera (`RACK_VIEW=game`, the
## default) or from a close-up camera where the player's aim camera is, behind the right shoulder,
## zoomed on the pistol (`RACK_VIEW=close`, 14 degrees), or from the character's right front,
## where the shoulder hides nothing (`RACK_VIEW=side`); `RACK_MODEL=male` puts the male body on
## the player. It prints a `RACK` line a frame (the reload's and the rack's weight and share, the
## slide's place).
##
## `gds capture frames --project game --scene res://tools/capture/rack_live.tscn --seconds 3.4
## --fps 30`. It lives in tools/, which the export leaves out.
extends Node3D

## Seconds from the start to the reload, for the game to settle.
const START := 0.5
## Where the close-up camera is, in the character's space (+Z its front): 1.1 m behind the 1.55 m
## target and 0.5 m to its right, as the aim camera is; and its field of view.
const CLOSE := Vector3(-0.5, 1.55, -1.1)
const CLOSE_FOV := 14.0
## Where the side camera is from the pistol, in the character's space, and its field of view.
const SIDE := Vector3(-0.42, 0.12, 0.3)
const SIDE_FOV := 32.0

var _player: Player
var _camera: Camera3D
var _age := 0.0
var _reloaded := false


func _ready() -> void:
	var main := (load("res://main.tscn") as PackedScene).instantiate()
	add_child(main)
	_player = main.get_node("PlayerRig/Player") as Player
	if OS.get_environment("RACK_MODEL") == "male":
		var slot := _player.model
		var old := slot.rig()
		slot.remove_child(old)
		old.free()
		slot.add_child((load(CharacterBodies.MALE) as PackedScene).instantiate())
	if OS.get_environment("RACK_VIEW") in ["close", "side"]:
		_camera = Camera3D.new()
		_camera.fov = CLOSE_FOV if OS.get_environment("RACK_VIEW") == "close" else SIDE_FOV
		_camera.near = 0.02
		add_child(_camera)
		_camera.make_current()


func _process(delta: float) -> void:
	_age += delta
	if not _reloaded and _age >= START:
		_reloaded = true
		_player.weapon.set_ammo(0, 24)
		_player.weapon.reload()
	var pistol := _player.get_node_or_null("Model/PistolHeld/Pistol") as Node3D
	if _camera != null and pistol != null:
		if OS.get_environment("RACK_VIEW") == "close":
			_camera.global_position = _player.model.global_transform * CLOSE
		else:
			_camera.global_position = pistol.global_position + _player.model.global_basis * SIDE
		_camera.look_at(pistol.global_position, Vector3.UP)
	var animation := _player.get_node("Animation") as CharacterAnimation
	var hold := _player.get_node("WeaponHold") as WeaponHold
	var slide := _player.get_node_or_null("Model/PistolHeld/Pistol/Pistol/Slide") as Node3D
	print(
		(
			"RACK %.3f reload %s rack %s slide %s ammo %s"
			% [
				_age,
				animation.reload_progress(),
				animation.rack.progress(),
				slide.position if slide != null else Vector3.ZERO,
				_player.weapon.ammo
			]
		)
	)
	if hold == null:
		get_tree().quit()
