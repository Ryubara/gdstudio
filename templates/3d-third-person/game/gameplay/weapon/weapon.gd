@tool
class_name Weapon
extends Node3D
## Shoots `Projectile`s from a muzzle toward the point its user aims at. It knows nothing about
## the model that carries it, and it reads no camera and no input: point `muzzle` at a marker on
## any gun, and `Player` (or anything else) calls `fire(origin, direction)` with the ray it aims
## along (for a human, the ray under the crosshair, which its `PlayerInput` puts in the command).
## `fire()` with no ray shoots straight out of the muzzle. A weapon with no muzzle (a character
## with no model, as a server has) still fires: from beside its `shooter`, `no_muzzle_offset`
## off the ray.
##
## Every number of a shot is here, in the inspector, and read when the shot is fired, so a change
## while the game runs shows in the next shot. The sound of a shot is the `ShotSound` node of
## `weapon.tscn` (its stream, volume, bus and voices are the node's own): five pistol shots picked
## at random with a small pitch and volume spread, up to three playing at once. A game swaps the
## sound by changing that one `stream`.

## A shot left the muzzle.
signal fired(projectile: Projectile)

@export_group("Nodes")
## Where the shot starts: a `Marker3D` on the model whose -Z points out of the barrel (the pistol's
## `Muzzle`).
@export var muzzle: Node3D
## The body that fires: the aim ray and the projectile skip it. Empty hits everything.
@export var shooter: CollisionObject3D
## Where a shot starts when there is no `muzzle`: this far from the point of the aim ray that is
## beside the shooter, in the ray's own axes (x to its right, y up, z back toward the shooter,
## so a negative z is out in front). The default is about where the pistol's muzzle is when the
## character aims.
@export var no_muzzle_offset := Vector3(0.07, -0.09, -0.65)

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
## What the aim ray hits (physics layers): what a shot meets (`PhysicsLayers.SHOT_MASK`: the
## level, characters, props and ragdoll bones), so the crosshair's point is on what the shot will
## hit.
@export_flags_3d_physics var aim_mask := PhysicsLayers.SHOT_MASK

@export_group("Projectile")
## How fast the projectile flies.
@export_range(5.0, 200.0, 0.5, "suffix:m/s") var projectile_speed := 45.0
## The projectile's diameter.
@export_range(0.02, 1.0, 0.01, "suffix:m") var projectile_size := 0.14
## How fast it falls; zero flies straight at the crosshair.
@export_range(0.0, 30.0, 0.1, "suffix:m/s²") var projectile_gravity := 0.0
## It disappears this long after it was fired.
@export_range(0.2, 20.0, 0.1, "suffix:s") var projectile_lifetime := 3.0
## The push it gives a physics body it hits (newton seconds), and the strength of its hit on a
## character (what pushes the body part it hits; the `HitReaction` scales it).
@export_range(0.0, 500.0, 0.5, "suffix:N·s") var projectile_impulse := 40.0
## The damage of a hit before the hit zone's multiplier (a head counts more, a limb less).
@export_range(0.0, 1000.0, 0.5, "or_greater") var projectile_damage := 34.0
## How many times it bounces off the level before it stops.
@export_range(0, 8, 1) var projectile_bounces := 0
## The share of its speed a bounce keeps.
@export_range(0.0, 1.0, 0.01) var projectile_bounce_keep := 0.6
## On: the shots leave marks, effects and sounds where they land (the level's `Impacts`). Off: this
## weapon's shots land without a trace, whatever the projectile scene says.
@export var impacts := true

@export_group("Muzzle flash")
## On: each shot flashes at the muzzle (particles and a light). Off: no flash for this weapon.
@export var muzzle_flash_enabled := true
## What flashes at the muzzle: an `EffectDef` the level's `EffectEmitter` plays on the `muzzle`
## marker, pointing out of its -Z. Give another weapon its own to change the look, its light or a
## sound. Empty makes none. A level with no `EffectEmitter` shows no flash.
@export_custom(PROPERTY_HINT_RESOURCE_TYPE, "EffectDef") var muzzle_flash: Resource
## Makes the flash bigger or smaller for this weapon (its particles and the reach of its light).
@export_range(0.1, 4.0, 0.05, "or_greater", "suffix:x") var muzzle_flash_size := 1.0

@export_group("Stepping")
## On: the weapon counts its own cooldown down, once a physics tick. Off: whoever steps the
## weapon calls `tick(delta)` instead. A `Player` turns it off for its weapon and ticks it at the
## end of each `step`, so the cooldown moves exactly when the body does (a server that steps a
## body twice in a frame, a body that is not stepped at all).
@export var self_ticking := true

var _cooldown := 0.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.seed = 1
	set_physics_process(not Engine.is_editor_hint())
	if not Engine.is_editor_hint() and muzzle_flash != null:
		var emitter := EffectEmitter.find(self)
		if emitter != null:
			emitter.warm(muzzle_flash)


func _physics_process(delta: float) -> void:
	if self_ticking:
		tick(delta)


## Moves the weapon one physics tick on: the cooldown counts down by `delta`. The cooldown is
## counted here and nowhere else (never read from a clock), so it is the same on every machine
## that steps the same ticks. Called by the weapon itself while `self_ticking` is on, else by
## whoever steps it.
func tick(delta: float) -> void:
	_cooldown = maxf(_cooldown - delta, 0.0)


## True when the weapon has somewhere to shoot from (a muzzle, or a shooter to stand beside)
## and a projectile, and is not cooling down.
func can_fire() -> bool:
	return (muzzle != null or shooter != null) and projectile_scene != null and _cooldown <= 0.0


## Fires one projectile and returns it, or null when it cannot fire yet. With a ray (`origin`
## and `direction`, what the shooter aims along) the shot leaves the muzzle toward the first
## thing the ray meets (`aim_point()`), or along the ray when that point is beside or behind
## the muzzle. With no ray it flies straight out of the muzzle.
func fire(origin := Vector3.INF, direction := Vector3.ZERO) -> Projectile:
	if not can_fire():
		return null
	var marker: Node3D = muzzle if muzzle != null else self
	var aimed := _is_ray(origin, direction)
	var along := direction.normalized() if aimed else -marker.global_basis.z
	var start := marker.global_position
	if aimed and muzzle == null:
		start = _bare_start(origin, along)
	var toward := aim_point(origin, direction) - start
	# A point beside or behind the gun (a wall at the character's back) would turn the shot
	# around: shoot along the aim instead.
	if toward.dot(along) <= 0.0 or toward.length() < 0.2:
		toward = along
	var heading := toward.normalized()
	if spread > 0.0:
		var angle := deg_to_rad(spread) * sqrt(_rng.randf())
		var around := _rng.randf() * TAU
		var side := heading.cross(Vector3.UP)
		if side.length_squared() < 0.0001:
			side = Vector3.RIGHT
		side = side.normalized()
		var up := side.cross(heading).normalized()
		heading = heading.rotated(side, sin(around) * angle).rotated(up, cos(around) * angle)
	var shot := projectile_scene.instantiate() as Projectile
	shot.size = projectile_size
	shot.gravity = projectile_gravity
	shot.lifetime = projectile_lifetime
	shot.impulse = projectile_impulse
	shot.damage = projectile_damage
	shot.bounces = projectile_bounces
	shot.bounce_keep = projectile_bounce_keep
	if not impacts:
		shot.impact_effects = false
	var world: Node = shooter.get_parent() if shooter != null else get_parent()
	world.add_child(shot)
	shot.launch(start, heading, projectile_speed, shooter)
	_cooldown = 1.0 / fire_rate
	_play_sound(start)
	_flash()
	fired.emit(shot)
	return shot


## The point a ray aims at: the first thing it hits (past the shooter), or the end of the ray
## (`aim_range`) when it hits nothing. The ray is looked along from the shooter's depth, so a
## wall between a camera and its character is not what the character aims at. With no ray it is
## the point straight out of the muzzle.
func aim_point(origin := Vector3.INF, direction := Vector3.ZERO) -> Vector3:
	if not _is_ray(origin, direction) or not is_inside_tree():
		var marker: Node3D = muzzle if muzzle != null else self
		return marker.global_position - marker.global_basis.z * aim_range
	var along := direction.normalized()
	var start := _at_shooter_depth(origin, along)
	var end := start + along * aim_range
	var query := PhysicsRayQueryParameters3D.create(start, end, aim_mask)
	if shooter != null:
		query.exclude = [shooter.get_rid()]
	var found := get_world_3d().direct_space_state.intersect_ray(query)
	return found["position"] if not found.is_empty() else end


## The cooldown and the place in the spread's seeded order, written into `kept`: the weapon's
## share of a character's step state (`CharacterState.weapon`).
func save_step_state(kept: Array) -> void:
	kept.resize(2)
	kept[0] = _cooldown
	kept[1] = _rng.state


## Puts back what `save_step_state()` wrote: the next shot leaves on the same tick and, with a
## spread, in the same direction as it would have then.
func load_step_state(kept: Array) -> void:
	if kept.size() < 2:
		return
	_cooldown = kept[0]
	_rng.state = kept[1]


func _is_ray(origin: Vector3, direction: Vector3) -> bool:
	return origin.is_finite() and direction.is_finite() and direction.length_squared() > 0.000001


# The ray's start moved along it to the shooter's depth (never back), so nothing behind the
# shooter is aimed at.
func _at_shooter_depth(origin: Vector3, along: Vector3) -> Vector3:
	if shooter == null:
		return origin
	return origin + along * maxf((shooter.global_position - origin).dot(along), 0.0)


# Where a shot starts with no muzzle: `no_muzzle_offset` from the ray beside the shooter.
func _bare_start(origin: Vector3, along: Vector3) -> Vector3:
	var side := along.cross(Vector3.UP)
	if side.length_squared() < 0.0001:
		side = Vector3.RIGHT
	side = side.normalized()
	var up := side.cross(along).normalized()
	return _at_shooter_depth(origin, along) + Basis(side, up, -along) * no_muzzle_offset


func _flash() -> void:
	if not muzzle_flash_enabled or muzzle_flash == null or muzzle == null:
		return
	var emitter := EffectEmitter.find(self)
	if emitter != null:
		emitter.play_on(muzzle_flash, muzzle, muzzle_flash_size)


func _play_sound(at: Vector3) -> void:
	var sound := get_node_or_null("%ShotSound") as AudioStreamPlayer3D
	if sound == null or sound.stream == null:
		return
	sound.global_position = at
	sound.play()


func _get_configuration_warnings() -> PackedStringArray:
	var warnings := PackedStringArray()
	if muzzle == null and shooter == null:
		(
			warnings
			. append(
				"Set `muzzle` (the marker the shots leave from) or, for a body with no model, `shooter`."
			)
		)
	if projectile_scene == null:
		warnings.append("Set `projectile_scene`: the scene made for each shot.")
	return warnings
