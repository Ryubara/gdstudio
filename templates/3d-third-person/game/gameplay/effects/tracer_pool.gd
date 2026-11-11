@tool
class_name TracerPool
extends MultiMeshInstance3D
## Draws the tracers of hitscan shots (a `WeaponDef`'s `tracer`, a `TracerDef`): one capped pool of
## streaks in the level, all drawn by one `MultiMesh`, so every tracer on the screen together is a
## single draw call and a shot makes no node. A weapon asks the level's pool (`TracerPool.find`) to
## `draw` a streak from its muzzle to where its ray ended; the pool runs each streak to its end,
## fades it and frees its place. When the pool is full the oldest streak is cut for the new one.
##
## Cosmetic: made on each screen from the shot it already has (its own ray, or a puppet's SHOT
## heading ended at the server's HIT: `end_near`), never sent. It does no work while nothing shows
## (hidden, `_process` off). Its first frames draw one unseen streak, so the web build links the
## streak's program while the level starts and not at the first shot.

## A streak was drawn from `from` to `to` (world space).
signal tracer_drawn(from: Vector3, to: Vector3)

## The group the level's pool is in (`find`).
const GROUP := &"tracer_pool"
## Half the size of the box the pool says it fills: the streaks are placed in the shader, so the
## pool is never culled while it shows (it is hidden when nothing does).
const BOUNDS := 4096.0

@export_group("Pool")
## On: hitscan shots draw their tracers. Off: none at all (a game's setting, a server).
@export var enabled := true:
	set(value):
		enabled = value
		if not enabled and is_node_ready():
			clear()
## The most streaks that show at once (the desktop). A newer one takes the oldest's place.
@export_range(1, 256, 1) var max_tracers := 32:
	set(value):
		max_tracers = value
		_resize()
## The most streaks that show at once in the web build and on phones.
@export_range(1, 256, 1) var web_max_tracers := 16:
	set(value):
		web_max_tracers = value
		_resize()

@export_group("Warm-up")
## Frames at the start that draw one unseen streak, so the first shot builds no program.
@export_range(0, 30, 1) var warm_up_frames := 3

## True in the web build and on phones: the pool is `web_max_tracers` there.
var compact := OS.has_feature("web") or OS.has_feature("mobile")

var _lines: Array[Line] = []
var _warm_left := 0
# What the multimesh was last given, instance by instance (a headless run's multimesh keeps none).
var _shown_transforms: Array[Transform3D] = []
var _shown_colors := PackedColorArray()
var _shown_energy := PackedFloat32Array()


## One streak: where it runs, how far, how long it has shown and how it looks.
class Line:
	extends RefCounted
	var from := Vector3.ZERO
	var heading := Vector3.FORWARD
	var distance := 0.0
	var age := 0.0
	var look: TracerDef

	## The point `metres` along the line.
	func at(metres: float) -> Vector3:
		return from + heading * clampf(metres, 0.0, distance)

	## The end of the line.
	func end() -> Vector3:
		return from + heading * distance

	## Where the head and the tail are now (metres from `from`), and how bright it is (0 to 1).
	func shape() -> Vector3:
		var travel := look.travel_time(distance)
		# It leaves the muzzle at its full length, so even the frame of the shot shows it.
		var head := distance
		if look.speed > 0.0:
			head = minf(look.length + look.speed * age, distance)
		var tail := maxf(head - look.length, 0.0) if look.speed > 0.0 else 0.0
		tail = minf(maxf(tail, look.start_offset), head)
		var fade := 1.0
		if age > travel:
			fade = 1.0 - (age - travel) / look.fade_time if look.fade_time > 0.0 else 0.0
		return Vector3(head, tail, clampf(fade, 0.0, 1.0))

	## True once the streak has run and faded.
	func done() -> bool:
		return age >= look.lifetime(distance)


## The pool drawn in the same viewport as `from` (several worlds in one process: a test, a
## side-by-side capture of two clients), the first otherwise, or null when the level has none.
static func find(from: Node) -> TracerPool:
	if from == null or not from.is_inside_tree():
		return null
	var viewport := from.get_viewport()
	var first: TracerPool = null
	for node in from.get_tree().get_nodes_in_group(GROUP):
		var found := node as TracerPool
		if found == null:
			continue
		if found.get_viewport() == viewport:
			return found
		if first == null:
			first = found
	return first


func _init() -> void:
	# After the weapons and the bodies have moved this frame.
	process_priority = 100
	top_level = true
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _enter_tree() -> void:
	if not Engine.is_editor_hint():
		add_to_group(GROUP)


func _ready() -> void:
	set_process(false)
	global_transform = Transform3D.IDENTITY
	_build()
	visible = false
	if Engine.is_editor_hint():
		return
	_warm_left = warm_up_frames
	if _warm_left > 0:
		_draw_warm()
		set_process(true)


func _process(delta: float) -> void:
	advance(delta)


## Draws a streak of `look` from `from` to `to`. Does nothing (and answers false) when the pool is
## off, `look` is empty or the two points are the same.
func draw(look: TracerDef, from: Vector3, to: Vector3) -> bool:
	if not enabled or look == null or not from.is_finite() or not to.is_finite():
		return false
	var distance := from.distance_to(to)
	if distance < 0.001:
		return false
	var line: Line = null
	if _lines.size() >= pool_cap():
		line = _lines.pop_front()
	else:
		line = Line.new()
	line.from = from
	line.heading = (to - from) / distance
	line.distance = distance
	line.age = 0.0
	line.look = look
	_lines.append(line)
	_warm_left = 0
	_write()
	set_process(true)
	tracer_drawn.emit(from, to)
	return true


## Ends every streak whose line passes within `radius` of `point`, ahead of where it started, at
## `point` (a puppet's tracer meets the server's HIT). Answers how many it ended.
func end_near(point: Vector3, radius: float) -> int:
	var ended := 0
	for line in _lines:
		var to_point := point - line.from
		var ahead := to_point.dot(line.heading)
		if ahead <= 0.0:
			continue
		if (to_point - line.heading * ahead).length() > radius:
			continue
		line.distance = to_point.length()
		line.heading = to_point / line.distance
		ended += 1
	if ended > 0:
		_write()
	return ended


## Ends the newest streak at `point` (a puppet's hitscan tracer drawn after the server's HIT that
## came with its SHOT). Answers false with no streak.
func end_newest_at(point: Vector3) -> bool:
	if _lines.is_empty():
		return false
	var line: Line = _lines.back()
	var to_point := point - line.from
	if to_point.length() < 0.001:
		return false
	line.distance = to_point.length()
	line.heading = to_point / line.distance
	_write()
	return true


## Moves every streak on by `delta` seconds and frees the places of those that ended. The process
## callback calls this; a test calls it to run a streak to its end at once.
func advance(delta: float) -> void:
	if _warm_left > 0:
		_warm_left -= 1
		if _warm_left == 0 and _lines.is_empty():
			_write()
			set_process(false)
		return
	for line in _lines:
		line.age += delta
	var kept: Array[Line] = []
	for line in _lines:
		if not line.done():
			kept.append(line)
	_lines = kept
	_write()
	set_process(not _lines.is_empty())


## Ends every streak now.
func clear() -> void:
	_lines.clear()
	_warm_left = 0
	_write()
	set_process(false)


## The most streaks the pool holds on this platform.
func pool_cap() -> int:
	return web_max_tracers if compact else max_tracers


## How many streaks show now.
func active_count() -> int:
	return _lines.size()


## Where streak `index` (0 the oldest) starts and ends now, world space: `[from, to]`, or an empty
## array.
func line_at(index: int) -> Array[Vector3]:
	if index < 0 or index >= _lines.size():
		return []
	var line := _lines[index]
	return [line.from, line.end()]


## How many instances the multimesh draws now (each streak that shows, or the warm-up's one).
func shown_count() -> int:
	return _shown_transforms.size()


## What instance `index` of the multimesh was given: `transform` (Y from the tail to the head, X as
## wide as the streak), `color` (alpha the fade) and `energy`; empty past `shown_count()`.
func shown(index: int) -> Dictionary:
	if index < 0 or index >= _shown_transforms.size():
		return {}
	return {
		"transform": _shown_transforms[index],
		"color": _shown_colors[index],
		"energy": _shown_energy[index],
	}


# The mesh, the multimesh and the room for the cap (the scene may hold the material).
func _build() -> void:
	if multimesh == null:
		multimesh = MultiMesh.new()
	else:
		multimesh = multimesh.duplicate()
	multimesh.instance_count = 0
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_colors = true
	multimesh.use_custom_data = true
	if multimesh.mesh == null:
		multimesh.mesh = QuadMesh.new()
	multimesh.custom_aabb = AABB(Vector3.ONE * -BOUNDS, Vector3.ONE * BOUNDS * 2.0)
	multimesh.instance_count = pool_cap()
	multimesh.visible_instance_count = 0


# A new cap while the game runs: the room for it, and the oldest streaks past it cut.
func _resize() -> void:
	if not is_node_ready() or multimesh == null or multimesh.instance_count == pool_cap():
		return
	while _lines.size() > pool_cap():
		_lines.pop_front()
	_warm_left = 0
	multimesh.instance_count = pool_cap()
	_write()
	set_process(not _lines.is_empty())


# Every streak that shows on the multimesh, the oldest first; hidden when there is none.
func _write() -> void:
	if multimesh == null:
		return
	_shown_transforms.clear()
	_shown_colors.clear()
	_shown_energy.clear()
	for line in _lines:
		var shape := line.shape()
		if shape.x - shape.y < 0.0005 or shape.z <= 0.0:
			continue
		var tint := line.look.color
		tint.a = shape.z
		_put(_segment(line.at(shape.y), line.at(shape.x), line.look.width), tint, line.look.energy)
	multimesh.visible_instance_count = _shown_transforms.size()
	visible = not _shown_transforms.is_empty()


func _put(placed: Transform3D, tint: Color, energy: float) -> void:
	var index := _shown_transforms.size()
	multimesh.set_instance_transform(index, placed)
	multimesh.set_instance_color(index, tint)
	multimesh.set_instance_custom_data(index, Color(energy, 0.0, 0.0, 0.0))
	_shown_transforms.append(placed)
	_shown_colors.append(tint)
	_shown_energy.append(energy)


# The instance transform of a streak from `tail` to `head`: Y along it, X as wide as it is.
static func _segment(tail: Vector3, head: Vector3, width: float) -> Transform3D:
	var axis := head - tail
	var heading := axis.normalized()
	var other := Vector3.UP if absf(heading.dot(Vector3.UP)) < 0.95 else Vector3.RIGHT
	var side := heading.cross(other).normalized()
	var depth := side.cross(heading).normalized()
	return Transform3D(Basis(side * width, axis, depth), (tail + head) * 0.5)


# One streak with no light at all, so the program is linked while the level starts.
func _draw_warm() -> void:
	var camera := get_viewport().get_camera_3d() if is_inside_tree() else null
	var at := Vector3.ZERO
	var forward := Vector3.FORWARD
	if camera != null:
		at = camera.global_position
		forward = -camera.global_basis.z
	_shown_transforms.clear()
	_shown_colors.clear()
	_shown_energy.clear()
	_put(_segment(at + forward * 2.0, at + forward * 3.0, 0.01), Color(0.0, 0.0, 0.0, 0.0), 0.0)
	multimesh.visible_instance_count = 1
	visible = true
