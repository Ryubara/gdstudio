class_name RemotePlayers
extends Node3D
## The other players of an online game, drawn on this screen: one puppet `Player` (the same
## `player.tscn` as the local body, `Player.make_puppet()`) a slot, placed `delay` seconds behind
## the newest snapshot, between the two snapshots around that moment (`InterpolationTrack`). Its
## `NetClient` hands it the WELCOME, every TICK and the `joined` and `left` events; it never sends
## anything. A puppet has no camera, so none takes the view
## (`camera.md#one-current-camera-per-viewport`).
##
## The clock: the server time of the newest TICK, moved on by each physics step in between and
## pulled a tenth of the way toward each TICK's time as it arrives, so jitter does not shake it; a
## clock `SNAP_SECONDS` off (a stall, a join) is set to the TICK's time.

## Said when a puppet was made (a join, or the first TICK that has the slot) and freed.
signal puppet_added(slot: int, puppet: Player)
signal puppet_removed(slot: int)

## Seconds off the newest TICK past which the clock jumps to it.
const SNAP_SECONDS := 0.3
## The share of the gap to a TICK's time the clock takes when the TICK arrives.
const CLOCK_PULL := 0.1

## The scene each puppet is made from.
@export var puppet_scene: PackedScene = preload("res://gameplay/player/player.tscn")
## Seconds behind the newest snapshot a puppet is drawn: three snapshots at 30 a second, so one
## late or lost one does not starve it.
@export_range(0.0, 0.5, 0.01, "suffix:s") var delay := 0.1
## Moves the puppets' animation on less often where the camera would not see it (off-screen, far),
## so a puppet's tree and skinning cost a browser frame only when it is seen (gdstudio #1138).
## Empty: every puppet animates every frame.
@export var animation_throttle: CharacterAnimationThrottle

## The local player's slot: no puppet is made for it.
var local_slot := -1
## The map's networked parts on this screen (`NetClient` hands them over at the WELCOME): a slab is
## drawn at the client's predicted tick, ahead of the moment a puppet is drawn at, so a puppet that
## stands on one is moved with it to where it is drawn.
var map_parts: NetWorld
## Puppet steps on which a puppet's track had no snapshot as new as the moment drawn: one count a
## starved puppet a physics step, so two starved puppets on one step count 2.
var starved := 0
## The microseconds the last physics step spent placing the puppets (their own animation and
## drawing are the characters' cost, not counted here).
var last_frame_us := 0

var _puppets: Dictionary[int, Player] = {}
var _tracks: Dictionary[int, InterpolationTrack] = {}
var _names: Dictionary[int, String] = {}
var _clock := -1.0
var _sample := PlayerEntry.new()


func _ready() -> void:
	# Before the bodies' own steps, so the animation of this tick reads this tick's place.
	process_physics_priority = -10


func _physics_process(delta: float) -> void:
	if _clock < 0.0:
		return
	var began := Time.get_ticks_usec()
	_clock += delta
	var at := _clock - delay
	for slot: int in _puppets:
		var track := _tracks[slot]
		var before := track.starved
		var moving := track.sample(at, _sample)
		_sample.position += _platform_shift(_sample.position, at)
		starved += 1 if track.starved > before else 0
		var puppet := _puppets[slot]
		var kept := puppet.move_goal.motion
		puppet.puppet_to(_sample, moving, delta)
		puppet.move_goal.motion = PlayerPuppet.goal_of(_sample, track.heading(), kept)
	last_frame_us = Time.get_ticks_usec() - began


## The puppet of `slot`, or null.
func puppet_at(slot: int) -> Player:
	return _puppets.get(slot)


## The slots with a puppet.
func slots() -> Array[int]:
	var out: Array[int] = _puppets.keys()
	out.sort()
	return out


## The name `slot` joined with ("" when unknown).
func name_of(slot: int) -> String:
	return _names.get(slot, "")


## Seconds of server time the puppets are drawn at, or -1 before the first TICK.
func drawn_time() -> float:
	return _clock - delay if _clock >= 0.0 else -1.0


## Every player present when this client joined (its own slot is skipped).
func on_welcome(welcome: SnapshotCodec.Welcome) -> void:
	local_slot = welcome.slot
	_clock = float(welcome.server_tick) / NetLimits.TICK_RATE
	for entry in welcome.players:
		if entry.slot != local_slot:
			_add(entry.slot, entry.player_name, entry)


## A TICK: each other player's entry joins its track (a puppet is made for a slot not seen yet).
func on_tick(tick: SnapshotCodec.Tick) -> void:
	var at := float(tick.server_tick) / NetLimits.TICK_RATE
	if _clock < 0.0 or absf(_clock - at) > SNAP_SECONDS:
		_clock = at
	else:
		_clock += (at - _clock) * CLOCK_PULL
	for entry in tick.players:
		if entry.slot == local_slot:
			continue
		if not _puppets.has(entry.slot):
			_add(entry.slot, _names.get(entry.slot, ""), entry)
		_tracks[entry.slot].push(at, entry)


func on_joined(slot: int, player_name: String) -> void:
	_names[slot] = player_name
	if _puppets.has(slot):
		_puppets[slot].name = _node_name(slot, player_name)


func on_left(slot: int) -> void:
	_names.erase(slot)
	_tracks.erase(slot)
	var puppet: Player = _puppets.get(slot)
	_puppets.erase(slot)
	if puppet != null:
		if animation_throttle != null and is_instance_valid(animation_throttle):
			animation_throttle.remove(puppet)
		puppet.queue_free()
		puppet_removed.emit(slot)


## Frees every puppet (the client left the game).
func clear() -> void:
	for slot: int in _puppets.keys():
		on_left(slot)
	_clock = -1.0


func _add(slot: int, player_name: String, entry: PlayerEntry) -> void:
	if slot == local_slot or _puppets.has(slot):
		return
	var puppet := puppet_scene.instantiate() as Player
	puppet.name = _node_name(slot, player_name)
	puppet.make_puppet()
	puppet.set_meta(NetHits.SLOT_META, slot)
	add_child(puppet)
	if puppet.weapon != null:
		puppet.weapon.authoritative = false
	PlayerPuppet.warp(puppet, entry)
	if animation_throttle != null:
		animation_throttle.add(puppet)
	_puppets[slot] = puppet
	_tracks[slot] = InterpolationTrack.new()
	if player_name != "":
		_names[slot] = player_name
	puppet_added.emit(slot, puppet)


# What the slab a puppet stands on at server time `at` moves between that moment and the tick this
# screen draws the slab at (the client's predicted command), so the puppet stands on the drawn slab.
func _platform_shift(point: Vector3, at: float) -> Vector3:
	if map_parts == null:
		return Vector3.ZERO
	var drawn_at := roundi(at * NetLimits.TICK_RATE)
	for entity in map_parts.movers():
		var platform := entity.part() as MovingPlatform
		if platform != null and platform.carries(point, drawn_at):
			return platform.position_at(map_parts.tick) - platform.position_at(drawn_at)
	return Vector3.ZERO


static func _node_name(slot: int, player_name: String) -> String:
	var shown := player_name.validate_node_name()
	return "Remote%d_%s" % [slot, shown] if shown != "" else "Remote%d" % slot
