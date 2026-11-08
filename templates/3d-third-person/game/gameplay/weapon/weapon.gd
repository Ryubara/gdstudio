@tool
class_name Weapon
extends Node3D
## Shoots `Projectile`s from a muzzle toward the point under the screen's centre (where the
## crosshair is). It knows nothing about the model that carries it: point `muzzle` at a marker
## on any gun, and `Player` (or anything else) calls `fire()`.
##
## Every number of a shot is here, in the inspector, and read when the shot is fired, so a change
## while the game runs shows in the next shot. The sound of a shot is the `ShotSound` node of
## `weapon.tscn` (its stream, volume and bus are the node's own): the template ships no pistol
## sound, so the slot is empty and nothing plays until a game puts one there.

## A shot left the muzzle.
signal fired(projectile: Projectile)

@export_group("Nodes")
## Where the shot starts: a `Marker3D` on the model whose -Z points out of the barrel (the pistol's
## `Muzzle`).
@export var muzzle: Node3D
## The body that fires: the aim ray and the projectile skip it. Empty hits everything.
@export var shooter: CollisionObject3D

@export_group("Fire")
## The projectile that is made for each shot.
@export var projectile_scene: PackedScene
## How many shots a second the weapon can fire.
@export_range(0.5, 30.0, 0.1, "suffix:shots/s") var fire_rate := 4.0
## On: holding the fire button keeps shooting. Off: one shot a press.
@export var automatic := false
## The shot goes off the aim by up to this angle, picked from a seeded sequence.
@export_range(0.0, 15.0, 0.1, "suffix:deg") var spread := 0.0
## The aim ray looks this far for something to hit; the shot flies toward the end of the ray when
## nothing is in the way.
@export_range(5.0, 500.0, 1.0, "suffix:m") var aim_range := 100.0
## What the aim ray hits (physics layers).
@export_flags_3d_physics var aim_mask := 1

@export_group("Projectile")
## How fast the projectile flies.
@export_range(5.0, 200.0, 0.5, "suffix:m/s") var projectile_speed := 45.0
## The projectile's diameter.
@export_range(0.02, 1.0, 0.01, "suffix:m") var projectile_size := 0.14
## How fast it falls; zero flies straight at the crosshair.
@export_range(0.0, 30.0, 0.1, "suffix:m/s²") var projectile_gravity := 0.0
## It disappears this long after it was fired.
@export_range(0.2, 20.0, 0.1, "suffix:s") var projectile_lifetime := 3.0
## The push it gives a physics body it hits (newton seconds).
@export_range(0.0, 500.0, 0.5, "suffix:N·s") var projectile_impulse := 40.0
## How many times it bounces off the level before it stops.
@export_range(0, 8, 1) var projectile_bounces := 0
## The share of its speed a bounce keeps.
@export_range(0.0, 1.0, 0.01) var projectile_bounce_keep := 0.6

var _cooldown := 0.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.seed = 1
	set_physics_process(not Engine.is_editor_hint())


func _physics_process(delta: float) -> void:
	_cooldown = maxf(_cooldown - delta, 0.0)


## True when the weapon has a muzzle and a projectile and is not cooling down.
func can_fire() -> bool:
	return muzzle != null and projectile_scene != null and _cooldown <= 0.0


## Fires one projectile toward the crosshair and returns it, or null when it cannot fire yet.
func fire() -> Projectile:
	if not can_fire():
		return null
	var origin := muzzle.global_position
	var direction := _direction_from(origin)
	if spread > 0.0:
		var angle := deg_to_rad(spread) * sqrt(_rng.randf())
		var around := _rng.randf() * TAU
		var side := direction.cross(Vector3.UP)
		if side.length_squared() < 0.0001:
			side = Vector3.RIGHT
		side = side.normalized()
		var up := side.cross(direction).normalized()
		direction = direction.rotated(side, sin(around) * angle).rotated(up, cos(around) * angle)
	var shot := projectile_scene.instantiate() as Projectile
	shot.size = projectile_size
	shot.gravity = projectile_gravity
	shot.lifetime = projectile_lifetime
	shot.impulse = projectile_impulse
	shot.bounces = projectile_bounces
	shot.bounce_keep = projectile_bounce_keep
	var world: Node = shooter.get_parent() if shooter != null else get_parent()
	world.add_child(shot)
	shot.launch(origin, direction, projectile_speed, shooter)
	_cooldown = 1.0 / fire_rate
	_play_sound(origin)
	fired.emit(shot)
	return shot


## The point the crosshair is over: the first thing the ray through the middle of the screen
## hits (past the shooter), or the end of the ray when it hits nothing. With no camera it is the
## point straight out of the muzzle.
func aim_point() -> Vector3:
	var camera := get_viewport().get_camera_3d() if is_inside_tree() else null
	if camera == null:
		var out := -muzzle.global_basis.z if muzzle != null else -global_basis.z
		var from := muzzle.global_position if muzzle != null else global_position
		return from + out * aim_range
	var centre := get_viewport().get_visible_rect().size / 2.0
	var ray := camera.project_ray_normal(centre)
	var start := camera.project_ray_origin(centre)
	if shooter != null:
		# Start the ray at the shooter's depth, so a wall behind the character is not hit.
		start += ray * maxf((shooter.global_position - start).dot(ray), 0.0)
	var end := start + ray * aim_range
	var query := PhysicsRayQueryParameters3D.create(start, end, aim_mask)
	if shooter != null:
		query.exclude = [shooter.get_rid()]
	var found := get_world_3d().direct_space_state.intersect_ray(query)
	return found["position"] if not found.is_empty() else end


func _direction_from(origin: Vector3) -> Vector3:
	var camera := get_viewport().get_camera_3d()
	var toward := aim_point() - origin
	var fallback := -muzzle.global_basis.z
	if camera != null:
		fallback = -camera.global_basis.z
		# A point beside or behind the gun (a wall at the character's back) would turn the shot
		# around: shoot along the view instead.
		if toward.dot(fallback) <= 0.0:
			toward = fallback
	if toward.length() < 0.2:
		toward = fallback
	return toward.normalized()


func _play_sound(at: Vector3) -> void:
	var sound := get_node_or_null("%ShotSound") as AudioStreamPlayer3D
	if sound == null or sound.stream == null:
		return
	sound.global_position = at
	sound.play()


func _get_configuration_warnings() -> PackedStringArray:
	var warnings := PackedStringArray()
	if muzzle == null:
		warnings.append("Set `muzzle`: the marker the shots leave from.")
	if projectile_scene == null:
		warnings.append("Set `projectile_scene`: the scene made for each shot.")
	return warnings
