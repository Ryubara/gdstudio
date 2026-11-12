extends Node
## What one shot costs, the pistol's projectile against its hitscan ray (`WeaponDef.hitscan`,
## gdstudio #1252), on a server and on a client, all of it: the call that fires and every tick of
## the round's flight (the physics move, its script, its end in the pool). One shot is fired every
## tick at a wall `WALL_DISTANCE` out, so in a steady run each tick holds one launch and one
## round's whole flight spread over the rounds in the air; a tick's time less a tick with no shot is
## one shot's full cost. The modes take turns in blocks of `BLOCK_TICKS`, `ROUNDS` times, and each
## answer is the median of its blocks, so a busy machine moves every mode alike.
##
## - **server:** the server's weapon (`authoritative` on, `effects` off: no sound, flash or mark),
##   fired from a body with no model along a ray, as `Character.step` fires it.
## - **client:** a puppet's shot (`Weapon.fire_cosmetic`: a cosmetic round for a projectile, nothing
##   for a ray), with its shot sound (`client`) and without (`client_silent`). The flash is the same
##   for both kinds and left out (no `EffectEmitter`).
##
## Run it headless on the desktop:
## `godot --headless --fixed-fps 60 --path game res://tools/bench/shot_cost.tscn`
## It prints one line of JSON that starts with `SHOT_COST`.

const WEAPON := "res://gameplay/weapon/weapon.tscn"
const PISTOL := "res://gameplay/weapon/pistol.tres"
const WALL_DISTANCE := 20.0
const BLOCK_TICKS := 300
const ROUNDS := 7
const MODES := [
	"idle",
	"server_projectile",
	"server_hitscan",
	"client_projectile",
	"client_hitscan",
	"client_silent_projectile",
	"client_silent_hitscan",
]

var _server: Weapon
var _client: Weapon
var _mode := ""
var _last_usec := 0
var _spent := 0
var _fire_spent := 0
var _ticks := 0
var _shots := 0
var _peak_in_air := 0
var _shot_sound: AudioStream


func _ready() -> void:
	var wall := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(40.0, 40.0, 1.0)
	shape.shape = box
	wall.add_child(shape)
	wall.position = Vector3(0.0, 1.0, -WALL_DISTANCE)
	add_child(wall)
	_server = _weapon("Server", true)
	_client = _weapon("Client", false)
	_shot_sound = _client.definition.shot_sound
	_run.call_deferred()


func _weapon(node_name: String, server: bool) -> Weapon:
	var shooter := CharacterBody3D.new()
	shooter.name = node_name + "Body"
	var capsule := CollisionShape3D.new()
	capsule.shape = CapsuleShape3D.new()
	shooter.add_child(capsule)
	shooter.position = Vector3(3.0 if server else -3.0, 0.9, 0.0)
	add_child(shooter)
	var weapon := load(WEAPON).instantiate() as Weapon
	weapon.name = node_name + "Weapon"
	weapon.self_ticking = false
	weapon.projectile_cap = 64
	weapon.shooter = shooter
	if server:
		weapon.effects = false
	else:
		weapon.authoritative = false
		var muzzle := Marker3D.new()
		muzzle.position = shooter.position + Vector3(0.2, 0.5, -0.6)
		add_child(muzzle)
		weapon.muzzle = muzzle
	add_child(weapon)
	var definition := (load(PISTOL) as WeaponDef).duplicate() as WeaponDef
	definition.magazine_size = 1000000
	weapon.definition = definition
	return weapon


func _physics_process(_delta: float) -> void:
	var now := Time.get_ticks_usec()
	if _mode != "" and _last_usec > 0:
		_spent += now - _last_usec
		_ticks += 1
	_last_usec = now
	if _mode == "" or _mode == "idle":
		return
	var started := Time.get_ticks_usec()
	var weapon := _server if _mode.begins_with("server") else _client
	weapon.make_ready()
	if _mode.begins_with("server"):
		var eye := weapon.shooter.global_position + Vector3.UP * 0.7
		weapon.pull(eye, Vector3.FORWARD)
	else:
		weapon.fire_cosmetic(weapon.muzzle.global_position, Vector3.FORWARD)
	_fire_spent += Time.get_ticks_usec() - started
	_shots += 1
	_peak_in_air = maxi(_peak_in_air, weapon.live_projectiles().size())


func _run() -> void:
	await get_tree().physics_frame
	var blocks := {}
	var fire := {}
	var in_air := {}
	for mode: String in MODES:
		blocks[mode] = []
		fire[mode] = []
		in_air[mode] = 0
	var nodes_at_start := Performance.get_monitor(Performance.OBJECT_NODE_COUNT)
	for _round in ROUNDS:
		for mode: String in MODES:
			await _block(mode, 60)
			await _block(mode, BLOCK_TICKS)
			blocks[mode].append(_spent / float(_ticks))
			fire[mode].append(_fire_spent / float(maxi(_shots, 1)))
			in_air[mode] = maxi(in_air[mode], _peak_in_air)
	var idle := _median(blocks["idle"])
	var result := {
		"tick_us_idle": snappedf(idle, 0.1),
		"wall_m": WALL_DISTANCE,
		"nodes_after": Performance.get_monitor(Performance.OBJECT_NODE_COUNT) - nodes_at_start,
	}
	for mode: String in MODES:
		if mode == "idle":
			continue
		result[mode] = {
			"shot_us": snappedf(_median(blocks[mode]) - idle, 0.1),
			"fire_call_us": snappedf(_median(fire[mode]), 0.1),
			"rounds_in_air": in_air[mode],
		}
	print("SHOT_COST ", JSON.stringify(result))
	AudioSettings.stop_players(get_tree().root)
	for _frame in 8:
		await get_tree().process_frame
	get_tree().quit()


# Runs `mode` for `ticks` ticks from a clean count; the rounds of the mode before land first.
func _block(mode: String, ticks: int) -> void:
	_mode = ""
	for _frame in 40:
		await get_tree().physics_frame
	for weapon in [_server, _client]:
		(weapon as Weapon).definition.hitscan = mode.ends_with("hitscan")
	var silent := mode.begins_with("client_silent")
	_client.definition.shot_sound = null if silent else _shot_sound
	# The weapon decodes its sound when its definition is set.
	_client.definition = _client.definition
	_mode = mode
	_last_usec = 0
	_spent = 0
	_fire_spent = 0
	_ticks = 0
	_shots = 0
	_peak_in_air = 0
	while _ticks < ticks:
		await get_tree().physics_frame
	_mode = ""


static func _median(values: Array) -> float:
	var sorted := values.duplicate()
	sorted.sort()
	return sorted[sorted.size() / 2]
