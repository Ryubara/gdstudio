class_name FireRequest
extends Node
## The server's side of a shot: a client asks to fire, the server decides and applies it.

## The weapon this request drives.
@export var weapon: Weapon
## The muzzle flash every peer shows.
@export var flash: Node3D

## Client to server: pull the trigger at `aim`.
@rpc("any_peer", "call_remote", "reliable")
func request_fire(damage: int, aim: Vector3) -> void:
	if not multiplayer.is_server():
		return
	weapon.look_at(weapon.global_position + aim)
	weapon.tuning.damage = damage
	if weapon.fire():
		show_flash.rpc()


## Server to everyone: draw the muzzle flash.
@rpc("authority", "call_local", "reliable")
func show_flash() -> void:
	flash.visible = true
	await get_tree().create_timer(0.05).timeout
	flash.visible = false
