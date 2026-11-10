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
## Frames a reflection probe that updates once takes to be drawn: its six faces and up to eight
## blur steps, one a frame, one probe at a time. From its first face on, what it reaches is drawn
## with another program, so the warm-up waits this long for each probe the camera sees.
const PROBE_FRAMES := 15
## How wide a warmed material's quad is (a mark, a decal): a speck in front of the camera.
const QUIET_QUAD_SIZE := 0.01
## The view the warm-up draws a probe's room into: a program does not depend on the picture's size.
const TOUR_VIEW_SIZE := Vector2i(160, 90)
## Its camera's field of view, and the six ways it looks inside each probe.
const TOUR_FOV := 90.0
## How far above the highest probe the warm-up draws the effects once more, outside every probe.
const ABOVE_PROBES := 10.0
const TOUR_FACINGS: Array[Vector3] = [
	Vector3.FORWARD, Vector3.BACK, Vector3.LEFT, Vector3.RIGHT, Vector3.UP, Vector3.DOWN
]

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
## On: the warm-up then visits every reflection probe, unseen, and draws the level, the effects,
## the specks and the meshes of `warm_up_groups` inside it, and once more outside every probe, so
## walking into a room with its own probe and the first shot there build nothing (about 25 frames
## a probe; in the web build entering such a room was a 120 to 160 ms frame and its first shot 64
## to 87 ms). Off: only what the camera sees at the start.
@export var warm_up_every_probe := true
## Groups whose nodes' meshes the warm-up draws inside every probe, as specks of their materials
## (the characters, the weapons they carry): a body that walks under a probe is drawn with another
## program there.
@export var warm_up_groups: Array[StringName] = []
## Effects to warm up besides those the level's weapons and impact surfaces register themselves.
@export var warm_up: Array[EffectDef] = []
## Materials the warm-up draws once on a speck of a quad, besides those registered with
## `warm_material()` (the impacts' marks): anything a shot makes that is not an effect.
@export var warm_up_materials: Array[Material] = []

## True in the web build and on phones: the pool is `web_max_effects` there.
var compact := OS.has_feature("web") or OS.has_feature("mobile")

var _slots: Array[EffectSlot] = []
var _warm_queue: Array[EffectDef] = []
var _warm_materials: Array[Material] = []
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
	for material in warm_up_materials:
		warm_material(material)
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


## Adds `material` to those the warm-up draws once on a speck of a quad (the impacts register their
## marks' materials): a shot's first mark then builds nothing. Does nothing after the warm-up.
func warm_material(material: Material) -> void:
	if material != null and _warming and not _warm_materials.has(material):
		_warm_materials.append(material)


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


# Waits two frames for the camera and then for the reflection probes it sees, then plays each
# registered effect in front of it, tiny and dim, beside a speck of each registered material, and
# frees the slots again. Then it does the same inside each probe the camera did not see.
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
	var drawn := not warm_slots.is_empty() or not _warm_materials.is_empty()
	if camera != null and enabled and warm_up_on_start and drawn:
		# A probe draws its faces over the next frames, and everything it reaches changes program
		# once it has begun: what is warmed before that is not what the first shot draws.
		var probes := _probes()
		var begun: Array[ReflectionProbe] = []
		for _frame in _start_probes(camera, probes, begun):
			await get_tree().process_frame
		await _draw_warm(warm_slots, camera.global_transform)
		if warm_up_every_probe:
			await _tour_probes(warm_slots, probes, begun, _group_materials())
	_warm_queue.clear()
	_warm_materials.clear()
	_warming = false
	warmed.emit()


# Plays every warm slot once at `eye` (a camera's place), two metres in front of it, with a speck of
# each registered material and of each of `more`, and frees them again.
func _draw_warm(
	warm_slots: Array[EffectSlot], eye: Transform3D, more: Array[Material] = []
) -> void:
	var spot := eye.origin - eye.basis.z * 2.0
	var materials := _warm_materials.duplicate()
	for material in more:
		if not materials.has(material):
			materials.append(material)
	var specks := _make_specks(spot, eye.basis, materials)
	# Twice: the renderer builds a different program for a surface that an omni light reaches, so
	# every effect is drawn with the lights off and then with them on.
	for with_lights in [false, true]:
		if with_lights and not lights_enabled:
			break
		for slot in warm_slots:
			var placed := Transform3D(Basis(), spot)
			slot.start(slot.effect, placed, null, 1.0, true, false, with_lights, true)
		if with_lights and warm_slots.is_empty() and not specks.is_empty():
			specks.append(_make_speck_light(spot))
		set_process(true)
		await get_tree().process_frame
		await get_tree().process_frame
		for slot in warm_slots:
			slot.stop(true)
	for speck in specks:
		speck.queue_free()


# Visits each probe in `probes`, with a camera of its own in a small view of the same world that
# nobody sees: it waits there for the probe to be drawn when it has not begun, looks around once
# (the level's surfaces inside are drawn with the probe's program), and draws the effects and the
# specks there, with one of each of `more` (the bodies that walk in). Even a probe the camera saw is
# visited: what is drawn inside it is also under the probe around it (two probes are another
# program). Without it walking into a room with its own probe built the character's programs, and
# the first shot there the effects' and the mark's (kit #981).
func _tour_probes(
	warm_slots: Array[EffectSlot],
	probes: Array[ReflectionProbe],
	begun: Array[ReflectionProbe],
	more: Array[Material]
) -> void:
	if probes.is_empty():
		return
	var view := SubViewport.new()
	view.name = &"WarmTour"
	view.size = TOUR_VIEW_SIZE
	view.own_world_3d = false
	view.msaa_3d = get_viewport().msaa_3d
	view.positional_shadow_atlas_size = get_viewport().positional_shadow_atlas_size
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	var eye := Camera3D.new()
	eye.fov = TOUR_FOV
	# Moved by hand from place to place: an interpolated camera reports (and culls with) where it was
	# the frame before, so it saw no probe at its first place.
	eye.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	view.add_child(eye)
	add_child(view)
	eye.make_current()
	for probe in probes:
		eye.global_transform = Transform3D(Basis(), probe.global_position)
		for _frame in _start_probes(eye, probes, begun):
			await get_tree().process_frame
		for facing in TOUR_FACINGS:
			var up := Vector3.BACK if absf(facing.y) > 0.5 else Vector3.UP
			eye.global_basis = Basis.looking_at(facing, up)
			await get_tree().process_frame
		eye.global_basis = Basis()
		await _draw_warm(warm_slots, eye.global_transform, more)
	# And once outside every probe, above them all: a part of the level no probe reaches draws its
	# effects without one, and so, now and then, did a shot in the room (one 26 to 45 ms program).
	eye.global_transform = Transform3D(Basis(), _above_probes(probes))
	await _draw_warm(warm_slots, eye.global_transform, more)
	view.queue_free()


# A place above every probe's box, in none of them.
func _above_probes(probes: Array[ReflectionProbe]) -> Vector3:
	var bounds := AABB()
	for index in probes.size():
		var probe := probes[index]
		var box := probe.global_transform * AABB(-probe.size / 2.0, probe.size)
		bounds = box if index == 0 else bounds.merge(box)
	return bounds.get_center() + Vector3.UP * (bounds.size.y / 2.0 + ABOVE_PROBES)


# The materials of the meshes of the nodes in `warm_up_groups`, each once.
func _group_materials() -> Array[Material]:
	var materials: Array[Material] = []
	for group in warm_up_groups:
		for member in get_tree().get_nodes_in_group(group):
			var meshes := member.find_children("*", "MeshInstance3D", true, false)
			if member is MeshInstance3D:
				meshes.append(member)
			for node in meshes:
				var mesh := node as MeshInstance3D
				if mesh.mesh == null:
					continue
				for index in mesh.get_surface_override_material_count():
					var material := mesh.get_active_material(index)
					if material != null and not materials.has(material):
						materials.append(material)
	return materials


## The frames the warm-up waits for the reflection probes `camera` sees to be drawn (the renderer
## draws only the probes in view, one at a time); none when no probe is in view.
func probe_frames(camera: Camera3D) -> int:
	var begun: Array[ReflectionProbe] = []
	return _start_probes(camera, _probes(), begun)


# The reflection probes of the scene that are shown.
func _probes() -> Array[ReflectionProbe]:
	var probes: Array[ReflectionProbe] = []
	for node in get_tree().root.find_children("*", "ReflectionProbe", true, false):
		var probe := node as ReflectionProbe
		if probe.is_visible_in_tree():
			probes.append(probe)
	return probes


# The frames to wait for the probes of `probes` that `camera` sees and that have not begun (one
# `PROBE_FRAMES` for each that updates once, one frame for one that updates always); adds them to
# `begun`.
func _start_probes(
	camera: Camera3D, probes: Array[ReflectionProbe], begun: Array[ReflectionProbe]
) -> int:
	var frames := 0
	var planes := camera.get_frustum()
	for probe in probes:
		if begun.has(probe) or not _in_view(probe, planes):
			continue
		begun.append(probe)
		var once := probe.update_mode == ReflectionProbe.UPDATE_ONCE
		frames += PROBE_FRAMES if once else 1
	return frames


# True when the box of `probe` is not wholly outside one of the camera's planes.
func _in_view(probe: ReflectionProbe, planes: Array[Plane]) -> bool:
	var half := probe.size / 2.0
	var corners: Array[Vector3] = []
	for index in 8:
		var local := Vector3(
			half.x if index & 1 else -half.x,
			half.y if index & 2 else -half.y,
			half.z if index & 4 else -half.z
		)
		corners.append(probe.global_transform * local)
	for plane in planes:
		var outside := true
		for corner in corners:
			if not plane.is_point_over(corner):
				outside = false
				break
		if outside:
			return false
	return true


# A speck of a quad for each of `materials` at `spot`, facing the camera, casting no shadow:
# drawing it once builds what the material's first real use needs.
func _make_specks(spot: Vector3, facing: Basis, materials: Array[Material]) -> Array[Node3D]:
	var specks: Array[Node3D] = []
	if materials.is_empty():
		return specks
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE * QUIET_QUAD_SIZE
	for material in materials:
		var speck := MeshInstance3D.new()
		speck.name = &"WarmSpeck"
		speck.mesh = quad
		speck.material_override = material
		speck.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(speck)
		speck.global_transform = Transform3D(facing, spot)
		specks.append(speck)
	return specks


# The light of the second pass when no effect brings one: the specks are drawn lit too.
func _make_speck_light(spot: Vector3) -> Node3D:
	var light := OmniLight3D.new()
	light.name = &"WarmLight"
	light.light_energy = 0.01
	light.shadow_enabled = false
	add_child(light)
	light.global_position = spot
	return light


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
