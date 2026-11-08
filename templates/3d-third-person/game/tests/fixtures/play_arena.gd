class_name PlayArena
extends Node3D
## A small flat world for a suite: a floor with its top at y = 0 and a player on it, no camera
## and no level, so a test sees only what it puts there. Free it with `auto_free`.

var player: Player


func _init() -> void:
	var floor_body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(60.0, 1.0, 60.0)
	shape.shape = box
	floor_body.add_child(shape)
	floor_body.position = Vector3(0.0, -0.5, 0.0)
	add_child(floor_body)


## Adds a static box whose top is at `top` metres, centred at `centre` (x, z).
func add_block(centre: Vector2, size: Vector3, top: float) -> StaticBody3D:
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	body.position = Vector3(centre.x, top - size.y / 2.0, centre.y)
	add_child(body)
	return body


## Puts a player at `spot`, facing -Z (the way a camera looking along -Z moves it).
func add_player(spot: Vector3) -> Player:
	player = load("res://gameplay/player/player.tscn").instantiate() as Player
	player.start_at_spawn = false
	player.position = spot
	add_child(player)
	player.facing = PI
	return player
