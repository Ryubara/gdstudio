@tool
class_name Weapon
extends Node3D
## Fires the `WeaponDef` it holds (`definition`): a `Projectile` from a pool, one hitscan ray or a
## melee blow, toward the point its user aims at, and counts the ammunition (a magazine, a
## reserve, a reload that puts the rounds in at its end, a click on an empty magazine). It knows
## nothing about the model that carries it, and it reads no camera and no input: point `muzzle` at
## a marker on any gun, and the character calls `pull(origin, direction)` with the ray it aims
## along (for a human, the ray under the crosshair, which its `PlayerInput` puts in the command).
## `fire()` with no ray shoots straight out of the muzzle. A weapon with no muzzle (a character
## with no model, as a server has) still fires: from beside its `shooter`, `no_muzzle_offset`
## off the ray.
##
## Every number of a shot is the definition's, read when the shot is fired, so a change while the
## game runs shows in the next shot. The sounds play through the nodes of `weapon.tscn`
## (`ShotSound`, `EmptySound`, `ReloadSound`, `DrawSound`: volume, bus and voices are the nodes'),
## with the streams of the definition, decoded once to PCM (`DecodedSounds`: an Ogg Vorbis start
## set its decoder up, about 250 µs a shot, a decoded one about 1 µs). A `WeaponLoadout` gives the
## weapon another definition when the character switches; the ammunition of each one is kept there.

## A shot left: `projectile` is the body that flies (null for a hitscan shot or a blow).
signal fired(projectile: Projectile)
## A hitscan shot or a blow hit something: `hit` has `collider`, `position`, `normal`, `from`,
## `damage` and, on a character, `record` (the `HitRecord` its `HitZones` delivered, the small
## record a network sends; a projectile reports its own hit).
signal hit_scanned(hit: Dictionary)
## The trigger was pulled on an empty magazine.
signal dry_fired
## The magazine or the reserve changed (a shot, a reload, ammunition picked up, a switch).
signal ammo_changed(ammo: int)
## A reload began; the rounds go in after `seconds`.
signal reload_started(seconds: float)
## A reload ended and the rounds are in.
signal reloaded
## A reload was cut short (a switch, a death): no round went in.
signal reload_cancelled
## The weapon was given another definition.
signal definition_changed(definition: WeaponDef)

## What a pull of the trigger did.
enum Pull {
	FIRED,  ## A shot (or a blow) left.
	EMPTY,  ## The magazine is empty: a click.
	BUSY,  ## Nothing: cooling down, reloading, put away, or nowhere to shoot from.
}

@export_group("Weapon")
## What the weapon is: its numbers, its projectile, its sounds and how it is held. Changing it
## fills the magazine and the reserve of the new one (a `WeaponLoadout` puts back what it kept).
@export var definition: WeaponDef:
	set(value):
		definition = value
		if not Engine.is_editor_hint() and is_node_ready():
			_apply_definition(true)
		update_configuration_warnings()

@export_group("Nodes")
## Where the shot starts: a `Marker3D` on the model whose -Z points out of the barrel (the pistol's
## `Muzzle`). A `WeaponLoadout` sets it from the definition's `muzzle`.
@export var muzzle: Node3D
## The body that fires: the aim ray and the shots skip it. Empty hits everything.
@export var shooter: CollisionObject3D
## Where a shot starts when there is no `muzzle`: this far from the point of the aim ray that is
## beside the shooter, in the ray's own axes (x to its right, y up, z back toward the shooter,
## so a negative z is out in front). The default is about where the pistol's muzzle is when the
## character aims.
@export var no_muzzle_offset := Vector3(0.07, -0.09, -0.65)
## What the aim ray hits (physics layers): what a shot meets (`PhysicsLayers.SHOT_MASK`: the
## level, characters, props, ragdoll bones and hit zones), so the crosshair's point is on what the
## shot will hit.
@export_flags_3d_physics var aim_mask := PhysicsLayers.SHOT_MASK

@export_group("Muzzle flash")
## On: each shot flashes at the muzzle (the definition's `muzzle_flash`). Off: no flash.
@export var muzzle_flash_enabled := true

@export_group("Pool")
## The most projectiles of this weapon in flight at once. A shot past it takes the oldest one
## back and fires it again, so a held trigger never makes bodies without end; a finished
## projectile waits out of the tree to be fired again.
@export_range(1, 256, 1) var projectile_cap := 24

@export_group("Stepping")
## On: the weapon counts its own cooldown and reload down, once a physics tick. Off: whoever steps
## the weapon calls `tick(delta)` instead. A `Character` turns it off for its weapon and ticks it
## at the end of each `step`, so the timers move exactly when the body does.
@export var self_ticking := true

## True while the weapon is put away (a `WeaponLoadout` switching): it does not fire or reload.
var lowered := false

## Rounds in the magazine, or null for a weapon with no ammunition (the HUD hides then).
var ammo: Variant:
	get:
		return _magazine if _uses_ammo() else null
## Rounds a full magazine holds, or null for a weapon with no ammunition.
var magazine_size: Variant:
	get:
		return definition.magazine_size if _uses_ammo() else null
## Rounds beside the magazine, or null for a weapon with no ammunition.
var reserve: Variant:
	get:
		return _reserve if _uses_ammo() else null

## The share of `spread` a shot gets now: the character that holds the weapon sets it each
## step (lying down is steadier, `ProneTuning.spread_share`); 1 alone.
var spread_share := 1.0

# Online play (gdstudio #906): the server's weapon is the one whose shots count; a client's are
# cosmetic, and a server's make no sound, flash or mark.
## On: the shots hit (damage, pushes, a `Health` or `HitZones` told). Off (a client online): the
## projectiles it fires are cosmetic (`Projectile.authoritative` off) and a ray or a blow
## touches nothing; the server's event says what was hit.
var authoritative := true
## On: the flash, the sounds and the impacts play. Off (a server): none of them.
var effects := true
## With 0 or more, the spread of a shot is drawn from a generator seeded by this and `shot_seq`
## (a player's slot and its command's number), so every peer draws the same pellet for one
## command whatever it fired before. -1: the weapon's own running order.
var seed_base := -1
## The number of the command being stepped (`Character.step` sets it).
var shot_seq := 0
## Where the last shot left from and the way it went (after the spread), world space.
var last_origin := Vector3.ZERO
var last_heading := Vector3.FORWARD
## The AI as the shooter's screen drew it (a server's lag compensation, gdstudio #1198): set for
## the step of one command with a shot block, its shots meet each AI character there (a hitscan
## at once, a projectile for its first `ShotRewind.flight_seconds`). Null: as it is now.
var rewind: ShotRewind
var _cooldown := 0.0
var _magazine := 0
var _reserve := 0
var _reload_left := 0.0
var _reload_sounds_played := 0
var _rng := RandomNumberGenerator.new()
var _live: Array[Projectile] = []
var _spare: Array[Projectile] = []
var _last_projectile: Projectile


func _ready() -> void:
	_rng.seed = 1
	set_physics_process(not Engine.is_editor_hint())
	if Engine.is_editor_hint():
		return
	if definition == null:
		definition = WeaponDef.new()
	_apply_definition(true)


func _notification(what: int) -> void:
	if what != NOTIFICATION_PREDELETE:
		return
	for shot in _spare:
		if is_instance_valid(shot):
			shot.queue_free()
	for shot in _live:
		if is_instance_valid(shot):
			shot.recycled = false


func _physics_process(delta: float) -> void:
	if self_ticking:
		tick(delta)


## Moves the weapon one physics tick on: the cooldown and a reload count down by `delta`, and an
## empty magazine with rounds in reserve starts a reload (`auto_reload`). Counted here and nowhere
## else (never from a clock), so it is the same on every machine that steps the same ticks.
func tick(delta: float) -> void:
	_cooldown = maxf(_cooldown - delta, 0.0)
	if _reload_left > 0.0:
		_reload_left = maxf(_reload_left - delta, 0.0)
		_play_reload_steps()
		if _reload_left <= 0.0:
			_finish_reload()
	elif definition != null and definition.auto_reload and _magazine == 0 and _cooldown <= 0.0:
		reload()


## True when a pull would fire now: somewhere to shoot from, not cooling down, reloading or put
## away, and a round in the magazine (or no magazine at all).
func can_fire() -> bool:
	if definition == null or lowered or _cooldown > 0.0 or _reload_left > 0.0:
		return false
	if _uses_ammo() and _magazine <= 0:
		return false
	if definition.shot_kind() == WeaponDef.Kind.PROJECTILE and definition.projectile_scene == null:
		return false
	return muzzle != null or shooter != null or definition.shot_kind() == WeaponDef.Kind.MELEE


## Pulls the trigger once along the ray `origin`, `direction` (or out of the muzzle with no ray):
## fires when it can, clicks on an empty magazine (spaced by the fire rate), and does nothing while
## cooling down, reloading or put away.
func pull(origin := Vector3.INF, direction := Vector3.ZERO) -> Pull:
	_last_projectile = null
	if definition == null or lowered or _cooldown > 0.0 or _reload_left > 0.0:
		return Pull.BUSY
	if _uses_ammo() and _magazine <= 0:
		_cooldown = definition.shot_interval()
		_play(_player(&"EmptySound"), _muzzle_point())
		dry_fired.emit()
		return Pull.EMPTY
	if not can_fire():
		return Pull.BUSY
	_shoot(origin, direction)
	return Pull.FIRED


## Fires one shot and returns its projectile, or null when no projectile left (not ready, empty,
## or a hitscan or melee weapon: `pull()` says which). With a ray (`origin` and `direction`, what
## the shooter aims along) the shot leaves the muzzle toward the first thing the ray meets
## (`aim_point()`), or along the ray when that point is beside or behind the muzzle. With no ray it
## flies straight out of the muzzle.
func fire(origin := Vector3.INF, direction := Vector3.ZERO) -> Projectile:
	if not can_fire():
		return null
	_shoot(origin, direction)
	return _last_projectile


## Makes the weapon ready to fire at once: no cooldown, no reload, a full magazine (a test, a
## game's cheat, a respawn).
func make_ready() -> void:
	_cooldown = 0.0
	_reload_left = 0.0
	if _uses_ammo() and _magazine < definition.magazine_size:
		_magazine = definition.magazine_size
		ammo_changed.emit(_magazine)


## Starts a reload when the magazine is not full and the reserve has a round: the rounds go in
## after the definition's `reload_time`. True when it started.
func reload() -> bool:
	if not can_reload():
		return false
	_reload_left = definition.reload_time
	_reload_sounds_played = 0
	_play_reload_steps()
	reload_started.emit(definition.reload_time)
	return true


## True when `reload()` would start one.
func can_reload() -> bool:
	return (
		_uses_ammo()
		and not lowered
		and _reload_left <= 0.0
		and _magazine < definition.magazine_size
		and _reserve > 0
	)


## Cuts a reload short: no round goes in.
func cancel_reload() -> void:
	if _reload_left <= 0.0:
		return
	_reload_left = 0.0
	reload_cancelled.emit()


## True while the weapon cools down after a shot (or a click): a pull now does nothing.
func is_cooling_down() -> bool:
	return _cooldown > 0.0


## Plays a shot the server fired for another player (a puppet's, online): a cosmetic projectile
## (no hit, no push) from the muzzle along `heading`, the flash and the shot sound. Counts no
## ammunition and starts no cooldown: the server keeps those. `origin` is where the server's
## shot left, used when the weapon has no muzzle. Returns the projectile (null for a ray or a
## blow, or with no definition).
func fire_cosmetic(origin: Vector3, heading: Vector3) -> Projectile:
	_last_projectile = null
	if definition == null or not heading.is_finite() or heading.length_squared() < 0.000001:
		return null
	var start := muzzle.global_position if muzzle != null and muzzle.is_inside_tree() else origin
	last_origin = start
	last_heading = heading.normalized()
	if definition.shot_kind() == WeaponDef.Kind.PROJECTILE and definition.projectile_scene != null:
		var was := authoritative
		authoritative = false
		_launch(start, last_heading)
		authoritative = was
	_play(_player(&"ShotSound"), start)
	if definition.shot_kind() != WeaponDef.Kind.MELEE:
		_flash()
	fired.emit(_last_projectile)
	return _last_projectile


## True while a reload runs.
func is_reloading() -> bool:
	return _reload_left > 0.0


## How far the reload is, 0 at its start to 1 at its end (0 with none).
func reload_progress() -> float:
	if _reload_left <= 0.0 or definition == null:
		return 0.0
	return 1.0 - _reload_left / maxf(definition.reload_time, 0.001)


## Puts `count` rounds in the reserve, up to the definition's `max_reserve`; returns how many went
## in.
func add_ammo(count: int) -> int:
	if not _uses_ammo() or count <= 0:
		return 0
	var room := maxi(definition.max_reserve - _reserve, 0)
	var taken := mini(count, room)
	if taken > 0:
		_reserve += taken
		ammo_changed.emit(_magazine)
	return taken


## Sets the magazine and the reserve (a `WeaponLoadout` putting back what a weapon had), each
## held to what the definition allows.
func set_ammo(magazine: int, in_reserve: int) -> void:
	if definition == null:
		return
	_magazine = clampi(magazine, 0, definition.magazine_size)
	_reserve = clampi(in_reserve, 0, maxi(definition.max_reserve, in_reserve))
	ammo_changed.emit(_magazine)


## Plays the definition's `draw_sound` (the weapon coming out of a switch).
func play_draw_sound() -> void:
	_play(_player(&"DrawSound"), _muzzle_point())


## The point a ray aims at: the first thing it hits (past the shooter), or the end of the ray
## (`aim_range`) when it hits nothing. The ray is looked along from the shooter's depth, so a
## wall between a camera and its character is not what the character aims at. With no ray it is
## the point straight out of the muzzle.
func aim_point(origin := Vector3.INF, direction := Vector3.ZERO) -> Vector3:
	var reach := _range()
	if not _is_ray(origin, direction) or not is_inside_tree():
		var marker: Node3D = muzzle if muzzle != null else self
		return marker.global_position - marker.global_basis.z * reach
	var along := direction.normalized()
	var start := _at_shooter_depth(origin, along)
	var end := start + along * reach
	var found := _cast(start, end)
	return found["position"] if not found.is_empty() else end


## The projectiles of this weapon in flight now.
func live_projectiles() -> Array[Projectile]:
	return _live.duplicate()


## The step state of the weapon, written into `kept`: the cooldown, the place in the spread's
## seeded order, the magazine, the reserve and the reload's time left (`CharacterState.weapon`).
func save_step_state(kept: Array) -> void:
	kept.resize(5)
	kept[0] = _cooldown
	kept[1] = _rng.state
	kept[2] = _magazine
	kept[3] = _reserve
	kept[4] = _reload_left


## Puts back what `save_step_state()` wrote: the next shot leaves on the same tick and, with a
## spread, in the same direction as it would have then, from the same magazine.
func load_step_state(kept: Array) -> void:
	if kept.size() < 2:
		return
	_cooldown = kept[0]
	_rng.state = kept[1]
	if kept.size() < 5:
		return
	var changed: bool = _magazine != kept[2] or _reserve != kept[3]
	_magazine = kept[2]
	_reserve = kept[3]
	_reload_left = kept[4]
	if changed:
		ammo_changed.emit(_magazine)


func _shoot(origin: Vector3, direction: Vector3) -> void:
	_last_projectile = null
	var marker: Node3D = muzzle if muzzle != null else self
	var aimed := _is_ray(origin, direction)
	var along := direction.normalized() if aimed else -marker.global_basis.z
	var start := marker.global_position
	var shot_kind := definition.shot_kind()
	if shot_kind == WeaponDef.Kind.MELEE:
		start = _at_shooter_depth(origin, along) if aimed else _shooter_chest()
	elif aimed and muzzle == null:
		start = _bare_start(origin, along)
	var heading := along
	if shot_kind != WeaponDef.Kind.MELEE:
		var toward := aim_point(origin, direction) - start
		# A point beside or behind the gun (a wall at the character's back) would turn the shot
		# around: shoot along the aim instead.
		if toward.dot(along) <= 0.0 or toward.length() < 0.2:
			toward = along
		heading = _spread(toward.normalized())
	last_origin = start
	last_heading = heading
	if _uses_ammo():
		_magazine -= 1
	_cooldown = definition.shot_interval()
	if shot_kind == WeaponDef.Kind.PROJECTILE:
		_launch(start, heading, _rewind_flight(start, heading))
	else:
		_scan(start, heading, definition.ray_reach(), _rewind_ray(start, heading))
	_play(_player(&"ShotSound"), start)
	if shot_kind != WeaponDef.Kind.MELEE:
		_flash()
	if _uses_ammo():
		ammo_changed.emit(_magazine)
	fired.emit(_last_projectile)


func _spread(heading: Vector3) -> Vector3:
	if definition.spread <= 0.0:
		return heading
	if seed_base >= 0:
		_rng.seed = hash([seed_base, shot_seq])
	var angle := deg_to_rad(definition.spread * spread_share) * sqrt(_rng.randf())
	var around := _rng.randf() * TAU
	var side := heading.cross(Vector3.UP)
	if side.length_squared() < 0.0001:
		side = Vector3.RIGHT
	side = side.normalized()
	var up := side.cross(heading).normalized()
	return heading.rotated(side, sin(around) * angle).rotated(up, cos(around) * angle)


# The rewind of a projectile leaving now: the drawn AI along its first `flight_seconds`.
func _rewind_flight(start: Vector3, heading: Vector3) -> ShotRewind:
	if rewind == null or not authoritative:
		return null
	var seconds := rewind.flight_seconds
	var reach := definition.projectile_speed * seconds
	return rewind.for_shot(
		start, heading, reach, 0.5 * definition.projectile_gravity * seconds * seconds
	)


# The rewind of a ray (a hitscan shot or a blow) leaving now.
func _rewind_ray(start: Vector3, heading: Vector3) -> ShotRewind:
	if rewind == null or not authoritative:
		return null
	return rewind.for_shot(start, heading, definition.ray_reach())


func _launch(start: Vector3, heading: Vector3, shot_rewind: ShotRewind = null) -> void:
	var shot := _take_projectile()
	var world: Node = shooter.get_parent() if shooter != null else get_parent()
	if shot.get_parent() != world:
		if shot.get_parent() != null:
			shot.get_parent().remove_child(shot)
		world.add_child(shot)
	shot.size = definition.projectile_size
	shot.tint = definition.projectile_tint
	shot.gravity = definition.projectile_gravity
	shot.lifetime = definition.projectile_lifetime
	shot.impulse = definition.impulse
	shot.bounces = definition.projectile_bounces
	shot.bounce_keep = definition.projectile_bounce_keep
	shot.damage = definition.damage
	shot.impact_effects = (
		definition.impacts and shot.scene_impact_effects and effects and authoritative
	)
	shot.authoritative = authoritative
	shot.rewind = shot_rewind
	shot.launch(start, heading, definition.projectile_speed, shooter)
	_live.append(shot)
	_last_projectile = shot


# A projectile to fire: a spare one, a new one while under the cap, else the oldest in flight.
func _take_projectile() -> Projectile:
	while not _spare.is_empty():
		var spare: Projectile = _spare.pop_back()
		if is_instance_valid(spare) and spare.scene_file_path == _scene_path():
			return spare
		if is_instance_valid(spare):
			spare.queue_free()
	for index in range(_live.size() - 1, -1, -1):
		if not is_instance_valid(_live[index]):
			_live.remove_at(index)
	if _live.size() >= projectile_cap:
		var oldest: Projectile = _live.pop_front()
		oldest.halt()
		_spare.erase(oldest)
		return oldest
	var made := definition.projectile_scene.instantiate() as Projectile
	made.recycled = true
	made.finished.connect(_on_projectile_finished)
	return made


func _scene_path() -> String:
	return definition.projectile_scene.resource_path if definition.projectile_scene != null else ""


# A finished projectile waits, parked where it is (hidden, out of the physics), to be fired again.
func _on_projectile_finished(shot: Projectile) -> void:
	_live.erase(shot)
	if not _spare.has(shot):
		_spare.append(shot)


# One ray from `start` along `heading`, `reach` long: the hit is pushed, told and reported. A
# character's capsule asks its `HitZones` for the part on the ray (`HitZones.shot`, the record it
# delivers to `take_hit`), anything else its `Health`; a ray that passes between the parts goes on
# past the capsule, as a projectile does.
# With `shot_rewind`, the AI characters near the ray are met where the shooter's screen drew them
# (`ShotRewind.nearer`) and left out of the physics query.
func _scan(start: Vector3, heading: Vector3, reach: float, shot_rewind: ShotRewind = null) -> void:
	var skip: Array[RID] = []
	if shot_rewind != null:
		skip = shot_rewind.excluded()
	var found := {}
	var record: HitRecord = null
	for _attempt in 3:
		found = _cast(start, start + heading * reach, skip, definition.ray_mask(aim_mask))
		if shot_rewind != null:
			found = shot_rewind.nearer(start, start + heading * reach, found)
		if found.is_empty():
			return
		var zones := HitZones.of(found["collider"])
		if zones == null:
			break
		if not authoritative:
			break
		record = zones.shot(
			found["collider"],
			found["position"],
			heading,
			definition.damage,
			definition.impulse,
			shooter as Node3D,
			found.get("centre", found["position"])
		)
		if record != null:
			zones.deliver(record)
			break
		skip.append((found["collider"] as CollisionObject3D).get_rid())
		if shot_rewind != null:
			shot_rewind.skip(found["collider"])
		found = {}
	if found.is_empty():
		return
	var collider: Object = found["collider"]
	var point: Vector3 = found["position"]
	var normal: Vector3 = found["normal"]
	if not authoritative:
		(
			hit_scanned
			. emit(
				{
					"collider": collider,
					"position": point,
					"normal": normal,
					"from": start,
					"damage": 0.0,
					"record": null,
				}
			)
		)
		return
	if collider is RigidBody3D:
		var body := collider as RigidBody3D
		body.apply_impulse(heading * definition.impulse, point - body.global_position)
	# Not a character's hit zones: whatever carries a `Health` (a `Target`, a crate) takes the shot.
	var health := Health.of(collider) if record == null else null
	if health != null:
		health.apply(
			HitRecord.shot(
				definition.damage, &"", &"", point, heading, definition.impulse, shooter as Node3D
			)
		)
	var impacts := (
		Impacts.find(self) if definition.impacts and effects and collider != null else null
	)
	if impacts != null:
		impacts.impact(collider, point, normal)
	(
		hit_scanned
		. emit(
			{
				"collider": collider,
				"position": point,
				"normal": normal,
				"from": start,
				"damage": definition.damage,
				"record": record,
			}
		)
	)


func _cast(start: Vector3, end: Vector3, skip: Array[RID] = [], mask := -1) -> Dictionary:
	if not is_inside_tree():
		return {}
	var query := PhysicsRayQueryParameters3D.create(start, end, aim_mask if mask < 0 else mask)
	var excluded: Array[RID] = skip.duplicate()
	if shooter != null:
		excluded.append(shooter.get_rid())
	query.exclude = excluded
	return get_world_3d().direct_space_state.intersect_ray(query)


func _range() -> float:
	return definition.aim_range if definition != null else 100.0


func _uses_ammo() -> bool:
	return definition != null and definition.uses_ammo()


# The new definition's sounds on the players, a full magazine and reserve, and the news.
func _apply_definition(refill: bool) -> void:
	if definition == null:
		return
	var shot_sound := _player(&"ShotSound")
	if shot_sound != null:
		shot_sound.stream = DecodedSounds.decoded(definition.shot_sound)
		shot_sound.volume_db = definition.shot_volume_db
	_set_stream(&"EmptySound", DecodedSounds.decoded(definition.empty_sound))
	_set_stream(&"DrawSound", DecodedSounds.decoded(definition.draw_sound))
	# Decoded now, while the weapon is set up, not at the reload's first step.
	DecodedSounds.decoded_all(definition.reload_sounds)
	if definition.muzzle_flash != null:
		var emitter := EffectEmitter.find(self)
		if emitter != null:
			emitter.warm(definition.muzzle_flash)
	_reload_left = 0.0
	if refill:
		_magazine = definition.magazine_size
		_reserve = definition.start_reserve
	definition_changed.emit(definition)
	ammo_changed.emit(_magazine)


func _set_stream(node_name: StringName, stream: AudioStream) -> void:
	var player := _player(node_name)
	if player != null:
		player.stream = stream


func _finish_reload() -> void:
	var wanted := definition.magazine_size - _magazine
	var moved := mini(wanted, _reserve)
	_magazine += moved
	_reserve -= moved
	ammo_changed.emit(_magazine)
	reloaded.emit()


# Plays each reload sound whose share of the reload has passed.
func _play_reload_steps() -> void:
	var player := _player(&"ReloadSound")
	if player == null or definition == null or not effects:
		return
	var steps := definition.reload_sounds
	var progress := reload_progress()
	while _reload_sounds_played < steps.size():
		var at := (
			definition.reload_sound_at[_reload_sounds_played]
			if _reload_sounds_played < definition.reload_sound_at.size()
			else 0.0
		)
		if progress < at:
			return
		var stream := steps[_reload_sounds_played]
		_reload_sounds_played += 1
		if stream != null:
			player.stream = DecodedSounds.decoded(stream)
			player.global_position = _muzzle_point()
			player.play()


func _is_ray(origin: Vector3, direction: Vector3) -> bool:
	return origin.is_finite() and direction.is_finite() and direction.length_squared() > 0.000001


# The ray's start moved along it to the shooter's depth (never back), so nothing behind the
# shooter is aimed at.
func _at_shooter_depth(origin: Vector3, along: Vector3) -> Vector3:
	if shooter == null:
		return origin
	return origin + along * maxf((shooter.global_position - origin).dot(along), 0.0)


# Where a blow with no ray starts: the shooter's chest, or the weapon itself.
func _shooter_chest() -> Vector3:
	if shooter == null:
		return global_position
	# Geometry: about the chest of a 1.8 m character.
	return shooter.global_position + Vector3.UP * 1.3


# Where a shot starts with no muzzle: `no_muzzle_offset` from the ray beside the shooter.
func _bare_start(origin: Vector3, along: Vector3) -> Vector3:
	var side := along.cross(Vector3.UP)
	if side.length_squared() < 0.0001:
		side = Vector3.RIGHT
	side = side.normalized()
	var up := side.cross(along).normalized()
	return _at_shooter_depth(origin, along) + Basis(side, up, -along) * no_muzzle_offset


func _muzzle_point() -> Vector3:
	if muzzle != null and muzzle.is_inside_tree():
		return muzzle.global_position
	return global_position if is_inside_tree() else Vector3.ZERO


func _flash() -> void:
	if not effects or not muzzle_flash_enabled or definition.muzzle_flash == null or muzzle == null:
		return
	var emitter := EffectEmitter.find(self)
	if emitter != null:
		emitter.play_on(definition.muzzle_flash, muzzle, definition.muzzle_flash_size)


func _player(node_name: StringName) -> AudioStreamPlayer3D:
	return get_node_or_null("%" + node_name) as AudioStreamPlayer3D


func _play(player: AudioStreamPlayer3D, at: Vector3) -> void:
	if not effects or player == null or player.stream == null or not player.is_inside_tree():
		return
	player.global_position = at
	player.play()


func _get_configuration_warnings() -> PackedStringArray:
	var warnings := PackedStringArray()
	if definition == null:
		warnings.append("Set `definition`: the WeaponDef this weapon fires.")
		return warnings
	if muzzle == null and shooter == null and definition.shot_kind() != WeaponDef.Kind.MELEE:
		(
			warnings
			. append(
				"Set `muzzle` (the marker the shots leave from) or, for a body with no model, `shooter`."
			)
		)
	if definition.shot_kind() == WeaponDef.Kind.PROJECTILE and definition.projectile_scene == null:
		warnings.append("The definition has no `projectile_scene`: the scene made for each shot.")
	return warnings
