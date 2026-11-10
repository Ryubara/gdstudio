@tool
class_name EffectEmitter
extends Node3D
## Plays one-shot effects from anywhere, from one pool. Put one in the level (`effect_emitter.tscn`;
## `world/world.tscn` has it); it joins the group `effect_emitter`, so a weapon, an impact or a
## pickup finds it with `EffectEmitter.find(self)` and needs no path. An `EffectDef` says what an
## effect is (particles, sound, light flash, length); this plays it:
##
## [codeblock]
## var emitter := EffectEmitter.find(self)
## if emitter != null:
##     emitter.play_at(spark_effect, hit_point, hit_normal)      # +Y along the normal
##     emitter.play_on(flash_effect, muzzle_marker)              # out of the marker's -Z
## [/codeblock]
##
## The pool is capped (`max_effects`, lower on the web) and made of `EffectSlot`s that are made when
## first needed and then reused, so a long fight makes no new nodes. An effect ends by itself and
## its slot is free again; when the pool is full the oldest effect is cut for the new one. Only the
## particles and the sound are cheap on the web, so the number of lights at once is capped too
## (`max_lights`). Everything here is cosmetic: it is made on each machine from what happened and
## never sent over the network.
##
## Every number is read when an effect plays, so a change while the game runs shows in the next one.

## An effect started in `slot`.
signal played(effect: EffectDef, slot: EffectSlot)
## The warm-up at the start of the level has drawn its effects and is over.
signal warmed

const GROUP := &"effect_emitter"

@export_group("Effects")
## Off: nothing plays, as if the emitter were not there.
@export var enabled := true
## On: effects show their particles.
@export var particles_enabled := true
## On: effects play their sound.
@export var sounds_enabled := true
## On: effects flash their light.
@export var lights_enabled := true

@export_group("Pool")
## How many effects can play at once on a computer or a console. A full pool cuts the oldest.
@export_range(0, 256, 1, "or_greater") var max_effects := 24:
	set(value):
		max_effects = maxi(value, 0)
		_trim()
## How many can play at once in the web build and on phones, which draw and mix less.
@export_range(0, 256, 1, "or_greater") var web_max_effects := 12:
	set(value):
		web_max_effects = maxi(value, 0)
		_trim()
## How many lights can flash at once. Past this an effect plays without its light.
@export_range(0, 8, 1) var max_lights := 2

@export_group("Warm up")
## On: the first frames of the level draw every effect once, unseen, in front of the camera, so the
## first shot does not stop the frame to build what drawing it needs (the web build did for 160
## to 340 ms each for the flash, its light and the impacts). Off: they are built when first played.
@export var warm_up_on_start := true
## Effects to warm up besides those the level's weapons and impact surfaces register themselves.
@export var warm_up: Array[EffectDef] = []

## True in the web build and on phones: the pool is `web_max_effects` there.
var compact := OS.has_feature("web") or OS.has_feature("mobile")

var _slots: Array[EffectSlot] = []
var _warm_queue: Array[EffectDef] = []
var _warming := true


## The emitter of the level `from` is in (the first in the group), or null when there is none.
static func find(from: Node) -> EffectEmitter:
	if from == null or not from.is_inside_tree():
		return null
	return from.get_tree().get_first_node_in_group(GROUP) as EffectEmitter


func _init() -> void:
	# After the animation and the nodes an effect follows have moved this frame.
	process_priority = 100
	top_level = true


func _enter_tree() -> void:
	if not Engine.is_editor_hint():
		add_to_group(GROUP)


func _ready() -> void:
	set_process(false)
	if Engine.is_editor_hint():
		return
	for def in warm_up:
		if def != null:
			warm(def)
	_warm_routine()


func _process(delta: float) -> void:
	advance(delta)


## Plays `effect` at `point`, standing on `direction` (its +Y; the surface normal at a hit).
## `with_particles` and `with_sound` leave a part out for this play. Returns the slot, or null when
## nothing played (the emitter or the effect is off).
func play_at(
	effect: EffectDef,
	point: Vector3,
	direction := Vector3.UP,
	with_particles := true,
	with_sound := true,
	size_scale := 1.0
) -> EffectSlot:
	var up := direction.normalized() if direction.length_squared() > 0.0001 else Vector3.UP
	var placed := Transform3D(Basis(Quaternion(Vector3.UP, up)), point)
	return _start(effect, placed, null, size_scale, with_particles, with_sound)


## Plays `effect` on `node` and keeps it there while it lasts: it points out of the node's -Z (a
## `Marker3D` on a barrel) and moves with it. `size_scale` multiplies the effect's own `size`.
func play_on(
	effect: EffectDef, node: Node3D, size_scale := 1.0, with_particles := true, with_sound := true
) -> EffectSlot:
	if node == null or not node.is_inside_tree():
		return null
	var base := node.global_transform.orthonormalized()
	var placed := Transform3D(base.basis * EffectSlot.FORWARD, base.origin)
	return _start(effect, placed, node, size_scale, with_particles, with_sound)


## Adds `effect` to those drawn once, unseen, at the start of the level (a weapon registers its
## flash, an impact surface its effect). After the warm-up is over it only builds the effect's slot.
func warm(effect: EffectDef) -> void:
	if effect == null or _warm_queue.has(effect):
		return
	if _warming:
		_warm_queue.append(effect)
	elif _slots.size() < pool_cap():
		_make_slot().prepare(effect)


## True while the warm-up is drawing its effects.
func is_warming() -> bool:
	return _warming


## Moves every effect on by `delta` seconds and frees the slots of those that ended. The process
## callback calls this; a test calls it to run an effect to its end at once.
func advance(delta: float) -> void:
	var busy := false
	for slot in _slots:
		if not slot.active:
			continue
		if slot.advance(delta):
			slot.stop(true)
		else:
			busy = true
	set_process(busy)


## Ends every effect now.
func stop_all() -> void:
	for slot in _slots:
		slot.stop(true)
	set_process(false)


## The most effects the pool holds on this platform.
func pool_cap() -> int:
	return web_max_effects if compact else max_effects


## How many effects are playing now.
func active_count() -> int:
	var count := 0
	for slot in _slots:
		if slot.active:
			count += 1
	return count


## How many lights are on now.
func light_count() -> int:
	var count := 0
	for slot in _slots:
		if slot.light_on():
			count += 1
	return count


## How many slots exist (playing or free): never more than `pool_cap()`.
func slot_count() -> int:
	return _slots.size()


## The slots, in the order they were made.
func slots() -> Array[EffectSlot]:
	return _slots


func _start(
	effect: EffectDef,
	placed: Transform3D,
	follow: Node3D,
	size_scale: float,
	with_particles: bool,
	with_sound: bool
) -> EffectSlot:
	if effect == null or not enabled or Engine.is_editor_hint():
		return null
	var slot := _take(effect)
	if slot == null:
		return null
	var with_light := lights_enabled and light_count() < max_lights
	slot.start(
		effect,
		placed,
		follow,
		size_scale,
		with_particles and particles_enabled,
		with_sound and sounds_enabled,
		with_light
	)
	set_process(true)
	played.emit(effect, slot)
	return slot


# The slot an effect plays in: a free one that already holds it, a new one while the effect and the
# pool have room, a free one of another effect, or the oldest playing one (of this effect when it
# is at its `max_instances`, of any when the pool is full).
func _take(effect: EffectDef) -> EffectSlot:
	if pool_cap() <= 0:
		return null
	var mine := 0
	var free_same: EffectSlot
	var free_other: EffectSlot
	var oldest_mine: EffectSlot
	var oldest_any: EffectSlot
	for slot in _slots:
		if slot.active:
			if oldest_any == null or slot.age > oldest_any.age:
				oldest_any = slot
			if slot.effect == effect and (oldest_mine == null or slot.age > oldest_mine.age):
				oldest_mine = slot
		elif slot.effect == effect and free_same == null:
			free_same = slot
		elif slot.effect != effect and free_other == null:
			free_other = slot
		if slot.effect == effect:
			mine += 1
	if free_same != null:
		return free_same
	if mine >= maxi(effect.max_instances, 1):
		return oldest_mine
	if _slots.size() < pool_cap():
		return _make_slot()
	return free_other if free_other != null else oldest_any


# Waits two frames for the camera, then plays each registered effect in front of it, tiny and dim,
# and frees the slots again.
func _warm_routine() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	var camera := get_viewport().get_camera_3d()
	var warm_slots: Array[EffectSlot] = []
	for def in _warm_queue:
		var slot := _take(def) if pool_cap() > 0 else null
		if slot != null:
			slot.prepare(def)
			warm_slots.append(slot)
	if camera != null and enabled and warm_up_on_start and not warm_slots.is_empty():
		var spot := camera.global_position - camera.global_basis.z * 2.0
		# Twice: the renderer builds a different program for a surface that an omni light reaches, so
		# every effect is drawn with the lights off and then with them on.
		for with_lights in [false, true]:
			if with_lights and not lights_enabled:
				break
			for slot in warm_slots:
				var placed := Transform3D(Basis(), spot)
				slot.start(slot.effect, placed, null, 1.0, true, false, with_lights, true)
			set_process(true)
			await get_tree().process_frame
			await get_tree().process_frame
			stop_all()
	_warm_queue.clear()
	_warming = false
	warmed.emit()


func _make_slot() -> EffectSlot:
	var slot := EffectSlot.new()
	_slots.append(slot)
	add_child(slot)
	return slot


# Frees slots that are not playing, then the oldest playing ones, until the pool fits its cap.
func _trim() -> void:
	if not is_inside_tree():
		return
	var cap := pool_cap()
	for slot in _slots.duplicate():
		if _slots.size() <= cap:
			return
		if not slot.active:
			_drop(slot)
	for slot in _slots.duplicate():
		if _slots.size() <= cap:
			return
		_drop(slot)


func _drop(slot: EffectSlot) -> void:
	slot.stop(true)
	_slots.erase(slot)
	slot.queue_free()
