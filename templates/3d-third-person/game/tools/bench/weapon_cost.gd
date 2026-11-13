extends Node
## What the weapon system costs on the CPU: a shot of each kind (a pooled projectile, a hitscan
## ray, a blow), the first shots that fill the pool, the tick of a weapon and its loadout, a burst
## weapon pulled on every tick as a character pulls it (gdstudio #1352), and how many objects a
## thousand shots leave behind. A wall 20 m out takes the projectiles back to the
## pool. Timed with `Time.get_ticks_usec()` around the calls only (never the physics server's
## step).
##
## Run it headless on the desktop:
## `godot --headless --fixed-fps 60 --path game res://tools/bench/weapon_cost.tscn`
## It prints one line of JSON that starts with `WEAPON_COST`.

const SHOTS := 1000
const TICKS := 20000
const WEAPON := "res://gameplay/weapon/weapon.tscn"
const PISTOL := "res://gameplay/weapon/pistol.tres"
const FISTS := "res://gameplay/weapon/fists.tres"


func _ready() -> void:
	var wall := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(40.0, 40.0, 1.0)
	shape.shape = box
	wall.add_child(shape)
	wall.position = Vector3(0.0, 1.0, -20.0)
	add_child(wall)
	_run.call_deferred()


func _run() -> void:
	await get_tree().physics_frame
	var result := {}
	var weapon := load(WEAPON).instantiate() as Weapon
	weapon.self_ticking = false
	add_child(weapon)
	var muzzle := Marker3D.new()
	muzzle.position = Vector3(0.0, 1.0, 0.0)
	add_child(muzzle)
	weapon.muzzle = muzzle
	var pistol := (load(PISTOL) as WeaponDef).duplicate() as WeaponDef
	pistol.magazine_size = SHOTS * 2
	weapon.definition = pistol
	# The first shots make the pool's bodies.
	var started := Time.get_ticks_usec()
	for _shot in weapon.projectile_cap:
		weapon.make_ready()
		weapon.fire()
	result["first_shots_us"] = (Time.get_ticks_usec() - started) / float(weapon.projectile_cap)
	var objects_before := Performance.get_monitor(Performance.OBJECT_COUNT)
	var resources_before := Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT)
	var spent := 0
	for _shot in SHOTS:
		weapon.make_ready()
		started = Time.get_ticks_usec()
		weapon.fire()
		spent += Time.get_ticks_usec() - started
		await get_tree().physics_frame
	result["projectile_shot_us"] = spent / float(SHOTS)
	result["objects_after_1000_shots"] = (
		Performance.get_monitor(Performance.OBJECT_COUNT) - objects_before
	)
	result["resources_after_1000_shots"] = (
		Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT) - resources_before
	)
	# The same shots with no sound: what the shot costs without its audio player.
	var silent := pistol.duplicate() as WeaponDef
	silent.shot_sound = null
	weapon.definition = silent
	spent = 0
	for _shot in SHOTS:
		weapon.make_ready()
		started = Time.get_ticks_usec()
		weapon.fire()
		spent += Time.get_ticks_usec() - started
		await get_tree().physics_frame
	result["projectile_shot_silent_us"] = spent / float(SHOTS)
	weapon.definition = pistol
	pistol.kind = WeaponDef.Kind.HITSCAN
	spent = 0
	for _shot in SHOTS:
		weapon.make_ready()
		started = Time.get_ticks_usec()
		weapon.pull(Vector3(0.0, 1.0, 3.0), Vector3.FORWARD)
		spent += Time.get_ticks_usec() - started
	result["hitscan_shot_us"] = spent / float(SHOTS)
	# A burst of three hitscan shots, silent, started every half second and pulled on every tick
	# while it is under way, as `Character._use_weapon` does: the tick and the pulls together.
	var burst := pistol.duplicate() as WeaponDef
	burst.fire_mode = WeaponDef.FireMode.BURST
	burst.shot_sound = null
	weapon.definition = burst
	weapon.make_ready()
	var bursts := 0
	started = Time.get_ticks_usec()
	for tick in TICKS:
		weapon.tick(1.0 / 60.0)
		if tick % 30 == 0:
			weapon.make_ready()
			bursts += 1
		if tick % 30 == 0 or weapon.bursting:
			weapon.pull(Vector3(0.0, 1.0, 3.0), Vector3.FORWARD)
	result["burst_tick_us"] = (Time.get_ticks_usec() - started) / float(TICKS)
	result["burst_us"] = (Time.get_ticks_usec() - started) / float(bursts)
	weapon.definition = load(FISTS) as WeaponDef
	spent = 0
	for _shot in SHOTS:
		weapon.make_ready()
		started = Time.get_ticks_usec()
		weapon.pull(Vector3(0.0, 1.0, 0.0), Vector3.FORWARD)
		spent += Time.get_ticks_usec() - started
	result["blow_us"] = spent / float(SHOTS)
	var loadout := WeaponLoadout.new()
	loadout.weapon = weapon
	loadout.slots = [pistol] as Array[Resource]
	loadout.unarmed = load(FISTS) as WeaponDef
	add_child(loadout)
	started = Time.get_ticks_usec()
	for tick in TICKS:
		if tick % 120 == 0:
			loadout.toggle_unarmed()
		loadout.tick(1.0 / 60.0)
		weapon.tick(1.0 / 60.0)
	result["tick_us"] = (Time.get_ticks_usec() - started) / float(TICKS)
	print("WEAPON_COST ", JSON.stringify(result))
	AudioSettings.stop_players(get_tree().root)
	for _frame in 8:
		await get_tree().process_frame
	get_tree().quit()
