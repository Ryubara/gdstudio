## Fires the rifle in the sample map the way a player would, next to a wall and then in the open,
## and measures on the screen what the muzzle flash's light does to the picture (kit
## docs/engines/godot/shot-feedback.md#flash-light). Each spot: the character is placed, the
## camera turned, the aim held and the fire button held for a burst of automatic fire.
##
## For every drawn frame with a flash light on, it draws the frame again with the effect lights
## hidden (`RenderingServer.force_draw`, kit measuring-effects-on-screen.md#method) and compares
## the two: `lit` the share of pixels the light changed, `gain` how much brighter they got (the
## mean of lit luma over unlit luma), `hue` the share of coloured pixels whose hue turned more
## than `HUE_DEGREES`, `clip` the share that the light pushed to white in a channel. Each frame is
## a `LIGHT` line, each burst ends with a `BURST` line of the worst frame and of the light's on
## time, and the run ends with `WALL` (how far the muzzle is from what it points at).
##
## Record it with Movie Maker through the kit (the frames land in the scratch folder), in both
## renderers: `gds capture frames --project game --scene res://tools/capture/muzzle_light_tour.tscn
## --seconds 30 --fps 30` and the same through `gds godot -- --path game --write-movie <png>
## --fixed-fps 30 --rendering-method gl_compatibility --scene ...` for the web look. It runs at
## `SLOW` times real speed so each flash takes several frames. It lives in tools/, which the
## export leaves out, and nothing in the game refers to it.
extends Node

enum Phase { PLACE, TURN, AIM, FIRE, REST, DONE }

const RIFLE := "res://gameplay/weapon/rifle.tres"
## The speed of the game while it films.
const SLOW := 0.25
## Camera turn speed toward a heading, in degrees a second of play.
const TURN_SPEED := 240.0
## A pixel is lit when the light changed a channel by more than this.
const LIT_STEP := 0.03
## A coloured pixel (saturation and value above `HUE_MIN`) whose hue turned more than this.
const HUE_DEGREES := 20.0
const HUE_MIN := 0.12
## Every `STRIDE`th pixel in each direction is read.
const STRIDE := 3

## The spots: where the character stands, the camera's yaw (0 looks along -Z) and pitch, and how
## long the fire button is held (seconds of play). The south wall's inner face is at z = 24.
const SPOTS: Array[Dictionary] = [
	{"name": "wall", "at": Vector3(4.0, 0.0, 22.6), "yaw": 160.0, "pitch": 4.0, "burst": 1.2},
	{"name": "open", "at": Vector3(-2.0, 0.0, 8.0), "yaw": 20.0, "pitch": 4.0, "burst": 1.2},
]

var _spot := 0
var _phase := Phase.PLACE
var _clock := 0.0
var _held: Array[StringName] = []
var _warmup := 1.0
var _measuring := false
var _worst := {}
var _on_frames := 0
var _frames := 0

@onready var _player: Player = $Main/PlayerRig/Player
@onready var _rig: PlayerCamera = $Main/PlayerRig/PlayerCamera
@onready var _emitter: EffectEmitter = $Main/World/Effects


func _ready() -> void:
	var rifle := load(RIFLE) as WeaponDef
	_try_light(rifle.muzzle_flash, OS.get_environment("MUZZLE_LIGHT"))
	_player.loadout.give(rifle, 300)
	RenderingServer.frame_post_draw.connect(_on_drawn)


func _physics_process(delta: float) -> void:
	if _warmup > 0.0:
		_warmup -= delta
		if _warmup <= 0.0:
			Engine.time_scale = SLOW
		return
	if _phase == Phase.DONE:
		return
	var spot := SPOTS[_spot]
	_clock += delta
	match _phase:
		Phase.PLACE:
			_hold([])
			_player.teleport(spot["at"])
			_next(Phase.TURN)
		Phase.TURN:
			_hold([])
			if _turn(spot["yaw"], spot["pitch"], delta) and _clock > 0.3:
				_next(Phase.AIM)
		Phase.AIM:
			_hold([&"aim"])
			_turn(spot["yaw"], spot["pitch"], delta)
			if _clock > 0.6:
				_worst = {"lit": 0.0, "gain": 1.0, "hue": 0.0, "clip": 0.0}
				_on_frames = 0
				_frames = 0
				print(
					"SPOT ",
					spot["name"],
					" wall ",
					snappedf(_muzzle_reach(), 0.01),
					" m frame ",
					_movie_frame()
				)
				_next(Phase.FIRE)
		Phase.FIRE:
			_hold([&"aim", &"fire"])
			_frames += 1
			if _emitter.light_count() > 0:
				_on_frames += 1
			if _clock >= float(spot["burst"]):
				_next(Phase.REST)
		Phase.REST:
			_hold([&"aim"])
			if _clock >= 0.6:
				_report(spot)
				_spot += 1
				if _spot >= SPOTS.size():
					_phase = Phase.DONE
					_hold([])
					_finish()
				else:
					_next(Phase.PLACE)


func _next(phase: Phase) -> void:
	_phase = phase
	_clock = 0.0


func _report(spot: Dictionary) -> void:
	print(
		"BURST ",
		spot["name"],
		" light_on_share ",
		snappedf(float(_on_frames) / maxf(_frames, 1), 0.01),
		" worst lit ",
		snappedf(_worst["lit"], 0.001),
		" gain ",
		snappedf(_worst["gain"], 0.01),
		" hue ",
		snappedf(_worst["hue"], 0.001),
		" clip ",
		snappedf(_worst["clip"], 0.001)
	)


# `MUZZLE_LIGHT=energy,range,attenuation,time[,r,g,b]` tries other light numbers on the flash.
func _try_light(flash: EffectDef, numbers: String) -> void:
	var parts := numbers.split(",", false)
	if parts.size() >= 4:
		flash.light_energy = float(parts[0])
		flash.light_range = float(parts[1])
		flash.light_attenuation = float(parts[2])
		flash.light_time = float(parts[3])
	if parts.size() >= 7:
		flash.light_color = Color(float(parts[4]), float(parts[5]), float(parts[6]))
	print(
		"FLASH energy ",
		flash.light_energy,
		" range ",
		flash.light_range,
		" attenuation ",
		flash.light_attenuation,
		" time ",
		flash.light_time,
		" colour ",
		flash.light_color
	)


# How far the muzzle is from the first thing straight out of it.
func _muzzle_reach() -> float:
	var muzzle := _player.weapon.muzzle
	if muzzle == null:
		return -1.0
	var from := muzzle.global_position
	var to := from - muzzle.global_basis.z.normalized() * 20.0
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.exclude = ShotHull.rids_of(_player)
	var hit := _player.get_world_3d().direct_space_state.intersect_ray(query)
	return from.distance_to(hit["position"]) if not hit.is_empty() else 20.0


# After each drawn frame with a flash light on: draws it again without the lights and compares.
func _on_drawn() -> void:
	if _measuring or _phase != Phase.FIRE and _phase != Phase.REST or _emitter.light_count() == 0:
		return
	_measuring = true
	var with_light := get_viewport().get_texture().get_image()
	var lights: Array[OmniLight3D] = []
	for slot in _emitter.slots():
		if slot.light_on():
			lights.append(slot.light())
			slot.light().visible = false
	RenderingServer.force_draw(false)
	var without := get_viewport().get_texture().get_image()
	for light in lights:
		light.visible = true
	RenderingServer.force_draw(false)
	var numbers := _compare(with_light, without)
	print(
		"LIGHT ",
		SPOTS[_spot]["name"],
		" frame ",
		_movie_frame(),
		" energy ",
		snappedf(lights[0].light_energy if not lights.is_empty() else 0.0, 0.01),
		" range ",
		snappedf(lights[0].omni_range if not lights.is_empty() else 0.0, 0.01),
		" lit ",
		snappedf(numbers["lit"], 0.001),
		" gain ",
		snappedf(numbers["gain"], 0.01),
		" hue ",
		snappedf(numbers["hue"], 0.001),
		" clip ",
		snappedf(numbers["clip"], 0.001)
	)
	if not _worst.is_empty():
		for key: String in numbers:
			_worst[key] = maxf(_worst[key], numbers[key])
	_measuring = false


func _compare(lit_image: Image, dark_image: Image) -> Dictionary:
	var size := lit_image.get_size()
	var total := 0
	var lit := 0
	var turned := 0
	var coloured := 0
	var clipped := 0
	var lit_luma := 0.0
	var dark_luma := 0.0
	for y in range(0, size.y, STRIDE):
		for x in range(0, size.x, STRIDE):
			var a := lit_image.get_pixel(x, y)
			var b := dark_image.get_pixel(x, y)
			total += 1
			var step := maxf(maxf(a.r - b.r, a.g - b.g), a.b - b.b)
			if step <= LIT_STEP:
				continue
			lit += 1
			lit_luma += a.get_luminance()
			dark_luma += b.get_luminance()
			if maxf(maxf(a.r, a.g), a.b) >= 0.99 and maxf(maxf(b.r, b.g), b.b) < 0.95:
				clipped += 1
			if b.s > HUE_MIN and b.v > HUE_MIN:
				coloured += 1
				var turn := absf(wrapf(a.h - b.h, -0.5, 0.5)) * 360.0
				if turn > HUE_DEGREES:
					turned += 1
	return {
		"lit": float(lit) / maxf(total, 1),
		"gain": lit_luma / maxf(dark_luma, 0.001) if lit > 0 else 1.0,
		"hue": float(turned) / maxf(total, 1),
		"clip": float(clipped) / maxf(total, 1),
	}


# The number of the Movie Maker file this frame is written to (the run counts from 0).
func _movie_frame() -> int:
	return Engine.get_process_frames()


func _finish() -> void:
	set_physics_process(false)
	Engine.time_scale = 1.0
	AudioSettings.stop_players(get_tree().root)
	for _frame in 8:
		await get_tree().process_frame
	get_tree().quit()


# Turns the camera toward a heading and a pitch; true when it is there.
func _turn(yaw: float, pitch: float, delta: float) -> bool:
	var by_yaw := clampf(
		wrapf(yaw - _rig.yaw, -180.0, 180.0), -TURN_SPEED * delta, TURN_SPEED * delta
	)
	var by_pitch := clampf(pitch - _rig.pitch, -TURN_SPEED * delta, TURN_SPEED * delta)
	_rig.orbit(Vector2(-by_yaw, by_pitch))
	return absf(wrapf(yaw - _rig.yaw, -180.0, 180.0)) < 1.0 and absf(pitch - _rig.pitch) < 1.0


# Holds exactly these actions down and lets go of the rest.
func _hold(actions: Array) -> void:
	for action in _held:
		if not actions.has(action):
			Input.action_release(action)
	_held.clear()
	for action: StringName in actions:
		Input.action_press(action)
		_held.append(action)
