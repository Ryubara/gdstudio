class_name AiReplica
extends Node3D
## The AI characters of an online game, drawn on this screen from the server's rows (gdstudio
## #970): the AI runs on the server only (`AiAuthority`), and each character here is a puppet, a
## dressed character with no AI part, no collision and no step of its own, placed by an `AiGlide`
## and animated from what the row says (its state, speed, aim). Its `NetClient` hands it the
## WELCOME, every TICK's AI block (`AiSnapshot`) and the AI events; it never sends anything.
##
## The clock is the server time of the newest TICK, moved on by each physics step and pulled a
## tenth of the way to each TICK's time (a clock `SNAP_SECONDS` off is set to it); the rows are
## drawn `interp_delay` behind it. A character's death (`NetEvent.AiCode.DIED`) starts its own
## ragdoll here from the pose it is in with the event's velocity; a shot (`FIRED`) is a cosmetic
## one from the puppet's muzzle; a HIT on it flinches it (`ClientCombat`). Nothing here is sent.

## Said when a puppet was made (its first row) and freed (it left this client's interest).
signal puppet_added(id: int, puppet: Character)
signal puppet_removed(id: int)
## Said when an AI event was played on a puppet.
signal event_played(event: NetEvent, puppet: Character)

const SNAP_SECONDS := 0.3
const CLOCK_PULL := 0.1

@export_group("Drawing")
## Seconds behind the newest TICK the rows are drawn: about three sends at 30 a second, so a late
## TICK does not starve a near character (a far one is sent less often and glides longer).
@export_range(0.0, 0.5, 0.005, "suffix:s") var interp_delay := 0.1
## Seconds a character is guessed ahead at its speed after its glide ends (never through a wall).
@export_range(0.0, 0.5, 0.01, "suffix:s") var extrapolate_seconds := 0.1
## Metres between two rows past which a character is set down, not walked there.
@export_range(0.5, 50.0, 0.1, "suffix:m") var glide_max_jump := 4.0
## What a guess ahead may not pass through.
@export_flags_3d_physics var extrapolate_mask := PhysicsLayers.WORLD
## The section's origin, the server's `ai_section_origin`: the rows are centimetres from it.
@export var section_origin := Vector3.ZERO
## The scene each look is drawn with: index n draws the characters of the server's
## `ai_variants[n]`. A dressed character with no AI part (`character_dressed.tscn` or one made
## from it); a look past the end draws the first.
@export var variant_scenes: Array[PackedScene] = [
	preload("res://gameplay/character/character_dressed.tscn")
]

## What this client holds (the rows, the sequence).
var snapshot := AiSnapshot.new()
var drops := NetDrops.new()
## Microseconds the last TICK's block took to apply (puppets made included), and the last physics
## step took to place every puppet; the most either took.
var last_apply_us := 0
var last_frame_us := 0
var worst_apply_us := 0
## While on, every TICK's apply time and every physics step's placing time are kept (a probe's).
var keep_times := false
var apply_times := PackedInt32Array()
var frame_times := PackedInt32Array()
## The most puppets drawn at once.
var most_puppets := 0
## `func(slot: int) -> Node3D`: a player's body on this screen (the `NetClient` sets it), for the
## aim of a character after that player.
var slot_body := Callable()

var _puppets: Dictionary[int, Character] = {}
var _glides: Dictionary[int, AiGlide] = {}
var _looks: Dictionary[int, int] = {}
var _clock := -1.0


func _ready() -> void:
	# A puppet made from an AI scene by mistake must not run the AI here.
	set_meta(AiAuthority.REMOTE_META, true)
	process_physics_priority = -10


func _physics_process(delta: float) -> void:
	if _clock < 0.0:
		return
	var began := Time.get_ticks_usec()
	_clock += delta
	var drawn := roundi((_clock - interp_delay) * NetLimits.TICK_RATE)
	var space := get_world_3d().direct_space_state if is_inside_tree() else null
	for id: int in _glides:
		var glide := _glides[id]
		glide.step(drawn, space, extrapolate_mask)
		_place(_puppets[id], glide, delta)
	last_frame_us = Time.get_ticks_usec() - began
	if keep_times:
		frame_times.append(last_frame_us)


## The puppet of AI id `id`, or null.
func puppet_of(id: int) -> Character:
	return _puppets.get(id)


## The glide of AI id `id`, or null.
func glide_of(id: int) -> AiGlide:
	return _glides.get(id)


## The ids with a puppet, sorted.
func ids() -> Array[int]:
	var out: Array[int] = _puppets.keys()
	out.sort()
	return out


func count() -> int:
	return _puppets.size()


## Seconds of server time the rows are drawn at, or -1 before the first TICK.
func drawn_time() -> float:
	return _clock - interp_delay if _clock >= 0.0 else -1.0


func on_welcome(server_tick: int) -> void:
	_clock = float(server_tick) / NetLimits.TICK_RATE


## A TICK: its AI block is applied (puppets made, rows queued, the gone freed).
func on_tick(tick: SnapshotCodec.Tick) -> void:
	var began := Time.get_ticks_usec()
	var at := float(tick.server_tick) / NetLimits.TICK_RATE
	if _clock < 0.0 or absf(_clock - at) > SNAP_SECONDS:
		_clock = at
	else:
		_clock += (at - _clock) * CLOCK_PULL
	if snapshot.apply(tick.ai, drops):
		for id in snapshot.gone:
			_remove(id)
		for id in snapshot.changed:
			var row: AiRow = snapshot.rows[id].copy()
			row.position += section_origin
			_puppet_for(id, row.variant)
			_glides[id].push(tick.server_tick, row)
	last_apply_us = Time.get_ticks_usec() - began
	worst_apply_us = maxi(worst_apply_us, last_apply_us)
	most_puppets = maxi(most_puppets, _puppets.size())
	if keep_times:
		apply_times.append(last_apply_us)


## Plays an AI event on its puppet (the client's `ClientCombat` hands it over when it is due).
func play_event(event: NetEvent) -> void:
	var puppet: Character = _puppets.get(event.id)
	if puppet == null:
		return
	match event.code:
		NetEvent.AiCode.DIED:
			if not puppet.is_dead():
				puppet.velocity = event.point
				puppet.die()
		NetEvent.AiCode.FIRED:
			if puppet.weapon != null and not puppet.is_dead():
				puppet.weapon.fire_cosmetic(event.point, event.direction)
	event_played.emit(event, puppet)


## Frees every puppet (the client left the game).
func clear() -> void:
	for id: int in _puppets.keys():
		_remove(id)
	snapshot.clear()
	_clock = -1.0


func _puppet_for(id: int, look: int) -> void:
	if _puppets.has(id) and _looks.get(id, -1) == look:
		return
	var kept: AiGlide = _glides.get(id)
	if _puppets.has(id):
		_remove(id)
	var scene := variant_scenes[look] if look < variant_scenes.size() else variant_scenes[0]
	var puppet := scene.instantiate() as Character
	puppet.name = "Ai%d" % id
	puppet.set_meta(NetHits.AI_META, id)
	puppet.ragdoll_by_command = false
	puppet.collision_layer = 0
	puppet.collision_mask = 0
	puppet.visible = false
	add_child(puppet)
	# After `_ready`: the engine turns physics processing on again for a node that becomes ready.
	puppet.set_physics_process(false)
	if puppet.weapon != null:
		puppet.weapon.authoritative = false
	var glide := kept if kept != null else AiGlide.new()
	glide.max_jump = glide_max_jump
	glide.extrapolate_ticks = roundi(extrapolate_seconds * NetLimits.TICK_RATE)
	_puppets[id] = puppet
	_glides[id] = glide
	_looks[id] = look
	puppet_added.emit(id, puppet)


func _remove(id: int) -> void:
	var puppet: Character = _puppets.get(id)
	_puppets.erase(id)
	_glides.erase(id)
	_looks.erase(id)
	if puppet != null:
		puppet.queue_free()
		puppet_removed.emit(id)


# The puppet where its glide is, animated as its row says.
func _place(puppet: Character, glide: AiGlide, delta: float) -> void:
	var row := glide.row
	if row == null:
		return
	if not puppet.visible:
		puppet.visible = true
		puppet.global_position = glide.position
		puppet.reset_physics_interpolation()
	if row.is_dead():
		# Its DIED event started the ragdoll; a row that says dead first does it here.
		if not puppet.is_dead():
			puppet.velocity = glide.velocity
			puppet.die()
		return
	if puppet.is_dead():
		puppet.revive_at(glide.position)
	puppet.global_position = glide.position
	puppet.velocity = glide.velocity
	puppet.facing = glide.yaw
	puppet.view_yaw = glide.yaw - PI
	puppet.view_pitch = _pitch_to(puppet, row.target)
	puppet._present_facing()
	if puppet.aiming != row.aiming:
		puppet.aiming = row.aiming
		puppet.aim_held = row.aiming
		puppet.aim_changed.emit(row.aiming)
	var tuning := puppet.tuning
	puppet.aim_amount = move_toward(
		puppet.aim_amount, 1.0 if row.aiming else 0.0, delta / maxf(tuning.aim_pose_time, 0.001)
	)
	var crouch := row.state == Character.State.CROUCH
	if puppet.crouching != crouch:
		puppet.crouching = crouch
		puppet.crouch_changed.emit(crouch)
	var before := puppet._crouch_amount
	puppet._crouch_amount = move_toward(
		puppet._crouch_amount, 1.0 if crouch else 0.0, delta / maxf(tuning.crouch_time, 0.001)
	)
	if puppet._crouch_amount != before:
		puppet._fit_body()
	if puppet.state != row.state:
		puppet.state = row.state as Character.State


# The aim's pitch toward what the row says it is after, when this screen has it; level otherwise.
func _pitch_to(puppet: Character, target: int) -> float:
	if target == AiSnapshot.NO_TARGET:
		return 0.0
	var body: Node3D = null
	var ai := NetHits.ai_id_of(target)
	if ai >= 0:
		body = _puppets.get(ai)
	elif NetHits.slot_of(target) >= 0:
		body = _body_of_slot(NetHits.slot_of(target))
	if body == null:
		return 0.0
	var eye := puppet.global_position + Vector3.UP * puppet.tuning.camera_height
	var aim_at := body.global_position + Vector3.UP * puppet.tuning.camera_height
	var way := aim_at - eye
	var flat := Vector2(way.x, way.z).length()
	return atan2(way.y, maxf(flat, 0.001))


func _body_of_slot(slot: int) -> Node3D:
	return slot_body.call(slot) as Node3D if slot_body.is_valid() else null
