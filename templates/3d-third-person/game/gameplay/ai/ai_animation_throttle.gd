class_name AiAnimationThrottle
extends Node
## Moves AI characters' animation on less often where nobody would see the difference
## (gdstudio #1046). The `AiDirector` hands it each character it manages (its
## `animation_throttle`); without one, every character animates every frame as the player does.
##
## Each character gets a **period** in frames, worked out again every `recheck_frames` on a frame
## of its own, from its director tier and from what the camera sees:
##
## - **every frame, as before** (the tree runs itself, untouched): nearer the camera than
##   `near_distance`, dead or in its ragdoll, or for `hit_hold` seconds after a hit (a flinch
##   moves the bones with physics);
## - **never** (the pose holds): at the Dormant tier, and out of the camera's view (no point of
##   the body inside its frustum);
## - otherwise `1` at the Full tier and `reduced_period` at Reduced, and at least `far_period`
##   farther from the camera than `far_distance`.
##
## A throttled tree is advanced by the time since its last advance, so the clips keep their speed;
## a frozen one, seen again, catches up `max_catch_up` seconds at most. Footsteps play only for a
## character animated every frame within `footstep_range` of the camera (the listener): a step is
## read from the feet, frame by frame. While a tree is throttled its `WeaponHold` puts the hand's
## weights on only when the tree advances, and its ragdoll keeps no per-tick pose for the bones'
## own velocities (a pose that moves every few frames has none worth keeping): a death in that
## time leaves with the character's velocity, as `pose_velocity` off does.
##
## Cosmetic and per machine: nothing here changes what the body does or what a network sends.

## Frames a new character animates as before: its tree starts by itself, and the level's camera
## has its place (a camera still at the origin on the first frame sees nobody).
const FIRST_FRAMES := 8
## The heights (m) of the body's points tested against the camera's view: feet, chest, head.
const BODY_POINTS: Array[float] = [0.2, 1.0, 2.2]

## Off: every character animates every frame (the throttle gives every tree back).
@export var enabled := true:
	set(value):
		enabled = value
		if is_inside_tree():
			_recheck_all()

@export_group("Distances")
## Nearer the camera than this, a character animates every frame whatever its tier: what the
## camera sees up close looks exactly as without the throttle.
@export_range(0.0, 200.0, 0.5, "suffix:m") var near_distance := 15.0
## Farther from the camera than this, a character animates every `far_period` frames at most.
@export_range(0.0, 500.0, 0.5, "suffix:m") var far_distance := 25.0
## Farther from the camera than this, no footstep sounds.
@export_range(0.0, 200.0, 0.5, "suffix:m") var footstep_range := 15.0

@export_group("Periods")
## Frames between two advances at the Reduced tier (in view, past `near_distance`).
@export_range(1, 30) var reduced_period := 3
## Frames between two advances past `far_distance` (in view).
@export_range(1, 30) var far_period := 6
## Off-screen characters hold their pose; off, they animate as if seen.
@export var freeze_unseen := true
## A frozen character seen again moves on at most this much at once.
@export_range(0.0, 2.0, 0.05, "suffix:s") var max_catch_up := 0.25
## Seconds a character animates every frame after a hit (a flinch is physics on the bones).
@export_range(0.0, 5.0, 0.05, "suffix:s") var hit_hold := 1.0

@export_group("Work")
## Frames between two checks of one character's period (each on a frame of its own).
@export_range(1, 60) var recheck_frames := 4
## On: the skeleton's modifiers (the hand on the weapon) run only when the tree advances too.
@export var throttle_skeleton := true
## The camera the distances and the view are measured from; empty: the viewport's camera.
@export var camera: Camera3D

## Frames since it started.
var frame := 0
## Trees that moved on the last frame, its own advances and the trees that run themselves (a
## count for tests and benches).
var last_advances := 0

var _entries: Array[Entry] = []
var _next_slot := 0
var _clock := 0.0


## A throttled character and its clock.
class Entry:
	var character: AiCharacter
	var animation: CharacterAnimation
	var footsteps: Footsteps
	var hold: WeaponHold
	var pose_velocity := false
	var slot := 0
	## Frames between advances: 1 the tree's own, 0 never.
	var period := 1
	var pending := 0.0
	var hit_until := 0.0
	## The frame it was added on: it is left alone for its first frames.
	var since := 0
	var on_hit: Callable
	var on_change: Callable
	var on_tier: Callable


## Takes `character`'s animation over (the director calls it when it registers one).
func add(character: AiCharacter) -> void:
	if character == null or _index_of(character) >= 0:
		return
	var entry := Entry.new()
	entry.character = character
	for child in character.get_children():
		if child is CharacterAnimation:
			entry.animation = child
		elif child is Footsteps:
			entry.footsteps = child
		elif child is WeaponHold:
			entry.hold = child
	if entry.animation == null:
		return
	entry.slot = _next_slot
	_next_slot += 1
	_entries.append(entry)
	# Bound to the character, not the entry: an entry holding a callable bound to itself is a
	# reference cycle that is never freed.
	entry.on_hit = _on_hit.bind(character).unbind(1)
	entry.on_change = _recheck_character.bind(character)
	entry.on_tier = entry.on_change.unbind(1)
	character.hit_received.connect(entry.on_hit)
	character.died.connect(entry.on_change)
	character.revived.connect(entry.on_change)
	character.tier_changed.connect(entry.on_tier)
	entry.since = frame


## Gives `character`'s animation back: it animates every frame again.
func remove(character: AiCharacter) -> void:
	var index := _index_of(character)
	if index < 0:
		return
	var entry := _entries[index]
	_entries.remove_at(index)
	if is_instance_valid(character):
		character.hit_received.disconnect(entry.on_hit)
		character.died.disconnect(entry.on_change)
		character.revived.disconnect(entry.on_change)
		character.tier_changed.disconnect(entry.on_tier)
	_set_period(entry, 1)


## How many characters it holds.
func count() -> int:
	return _entries.size()


## The period (frames between advances, 1 every frame, 0 never) `character` has now; -1 when it
## is not held.
func period_of(character: AiCharacter) -> int:
	var index := _index_of(character)
	return _entries[index].period if index >= 0 else -1


func _exit_tree() -> void:
	for entry in _entries:
		_set_period(entry, 1)


func _process(delta: float) -> void:
	frame += 1
	_clock += delta
	last_advances = 0
	for entry in _entries:
		if (frame + entry.slot) % recheck_frames == 0:
			_recheck(entry)
		match entry.period:
			1:
				last_advances += 1
			0:
				entry.pending = minf(entry.pending + delta, max_catch_up)
			_:
				entry.pending += delta
				if (frame + entry.slot) % entry.period == 0:
					_advance(entry)
					last_advances += 1


# A new character keeps its tree's own clock for `FIRST_FRAMES`: it is often placed after it joins
# the tree, the camera may not be placed yet, and a tree's first update starts its state machine,
# so a tree throttled before it runs would start out of step with one that never was.
func _recheck(entry: Entry) -> void:
	if not is_instance_valid(entry.character) or frame - entry.since < FIRST_FRAMES:
		return
	_set_period(entry, _period_for(entry))


func _recheck_character(character: AiCharacter) -> void:
	var index := _index_of(character)
	if index >= 0:
		_recheck(_entries[index])


func _recheck_all() -> void:
	for entry in _entries:
		_recheck(entry)


# The frames between advances `entry` should have now (see the class notes).
func _period_for(entry: Entry) -> int:
	var character := entry.character
	if _every_frame(entry):
		return 1
	if character.tier == AiDirector.Tier.DORMANT:
		return 0
	var tier_period := 1 if character.tier == AiDirector.Tier.FULL else reduced_period
	var view := _camera()
	if view == null:
		return tier_period
	var spot := character.global_position
	var distance := view.global_position.distance_to(spot)
	if distance <= near_distance:
		return 1
	if freeze_unseen and not _seen(view, spot):
		return 0
	return maxi(tier_period, far_period) if distance > far_distance else tier_period


# True when the tree must run every frame whatever the tier and the view: the throttle is off,
# or the character is dead, in its ragdoll or just hit.
func _every_frame(entry: Entry) -> bool:
	var character := entry.character
	var ragdoll := character.ragdoll_body
	return (
		not enabled
		or character.is_dead()
		or (ragdoll != null and ragdoll.is_active())
		or _clock < entry.hit_until
	)


# Moves `entry` to `period`: the tree is handed over or given back, a frozen tree catches up when
# it moves again, and the footsteps listen only every frame and near the camera.
func _set_period(entry: Entry, period: int) -> void:
	var animation := entry.animation
	if not is_instance_valid(animation):
		return
	if period != entry.period:
		if period == 1:
			_advance(entry)
			animation.set_throttled(false)
			_hand_over(entry, false)
		else:
			if entry.period == 1:
				animation.set_throttled(true, throttle_skeleton)
				_hand_over(entry, true)
			elif entry.period == 0:
				# Seen again: at once, not on its next slot.
				entry.period = period
				_advance(entry)
		entry.period = period
	if entry.footsteps != null and is_instance_valid(entry.footsteps):
		# A character that left the tree first (its map is being freed) has no place to hear.
		var hears := entry.character.is_inside_tree() and _hears(entry.character.global_position)
		entry.footsteps.set_listening(period == 1 and hears)


# Moves a throttled tree on by the time since its last advance, and the hand's weights with it.
func _advance(entry: Entry) -> void:
	entry.animation.advance(entry.pending)
	entry.pending = 0.0
	if entry.hold != null and is_instance_valid(entry.hold):
		entry.hold.refresh()


# The parts that follow the tree every frame stop while it is throttled (`on`) and start again.
func _hand_over(entry: Entry, on: bool) -> void:
	if entry.hold != null and is_instance_valid(entry.hold):
		entry.hold.set_process(not on)
	var ragdoll := entry.character.ragdoll_body
	if ragdoll == null or not is_instance_valid(ragdoll):
		return
	if on:
		entry.pose_velocity = ragdoll.pose_velocity
		ragdoll.pose_velocity = false
	else:
		ragdoll.pose_velocity = entry.pose_velocity


func _hears(spot: Vector3) -> bool:
	var view := _camera()
	return view == null or view.global_position.distance_to(spot) <= footstep_range


func _seen(view: Camera3D, spot: Vector3) -> bool:
	for height in BODY_POINTS:
		if view.is_position_in_frustum(spot + Vector3.UP * height):
			return true
	return false


func _camera() -> Camera3D:
	if camera != null and is_instance_valid(camera):
		return camera
	return get_viewport().get_camera_3d() if is_inside_tree() else null


func _on_hit(character: AiCharacter) -> void:
	var index := _index_of(character)
	if index < 0:
		return
	var entry := _entries[index]
	entry.hit_until = _clock + hit_hold
	_recheck(entry)


func _index_of(character: AiCharacter) -> int:
	for index in _entries.size():
		if _entries[index].character == character:
			return index
	return -1
