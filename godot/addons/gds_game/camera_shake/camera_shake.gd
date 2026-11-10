@tool
class_name CameraShake
extends Node
## The screen shake of a camera, "trauma" style, for any GDStudio game. Put one under a camera rig;
## anything can then shake the view in one line, with a `ShakePreset` (a resource):
##
## [codeblock]
## const BLAST := preload("res://<your presets>/explosion.tres")
## CameraShake.shake(BLAST, blast.global_position)
## [/codeblock]
##
## A one-shot adds trauma that drains away on its own; a held source (`hold`) keeps a preset going
## at a level until it is released. Plays far from the camera fall off with the preset's `radius`,
## and the global `strength` turns every shake down or off (an accessibility setting).
##
## This node only works out the turn; the rig that owns the camera applies it, on top of its own
## framing: `rotation_degrees()` is the turn of the view (x pitch, y yaw, z roll) and
## `view_offset()` the slide of the picture, in metres. Step it with `advance(delta)` from the rig
## (a test steps it by hand), or leave `auto_advance` on. Everything is a function of the steps it
## was given, never of the clock, and nothing here is sent over a network: a shake is the local
## player's own view.

## The group every shaker joins, so `shake()` finds them.
const GROUP := &"camera_shake"

## The noise of each axis is read from its own line of one noise field.
const AXIS_SPACING := 37.0

## The share of every shake that is felt, 0 to 1, in every game camera: 0 turns them all off.
## A settings menu sets it (the player's "camera shake" option, or reduced motion).
static var strength := 1.0

## Off turns this camera's shake off (a cutscene camera) and forgets what is running.
@export var enabled := true:
	set(value):
		enabled = value
		if not value:
			clear()
## How much of every shake this camera shows, on top of the global `strength`.
@export_range(0.0, 2.0, 0.05) var camera_strength := 1.0
## Where distance is measured from, for a play at a world position. Empty measures from the
## viewport's current camera.
@export var reference: Node3D
## Steps itself every frame. Turn it off when the rig calls `advance()` itself.
@export var auto_advance := true
## The seed of the noise.
@export var noise_seed := 1958:
	set(value):
		noise_seed = value
		_noise.seed = value

var _noise := FastNoiseLite.new()
var _shots: Dictionary = {}
var _held: Dictionary = {}
var _rotation := Vector3.ZERO
var _offset := Vector2.ZERO
var _dirty := false


## A shake in progress: the trauma of one preset and how long it has run.
class _Shot:
	var preset: ShakePreset
	var trauma := 0.0
	var time := 0.0


## A source that is kept going: the level it is easing to and the one it is at.
class _Held:
	var preset: ShakePreset
	var target := 0.0
	var level := 0.0
	var phase := 0.0


## Plays `preset` once on every camera with a shaker. `at` is a world position (a `Vector3`) for a
## shake that fades with distance from the camera; leave it out for one felt in full. `scale`
## multiplies the trauma (a bigger blast, a weaker graze).
static func shake(preset: ShakePreset, at: Variant = null, scale := 1.0) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or preset == null:
		return
	for node in tree.get_nodes_in_group(GROUP):
		(node as CameraShake).add(preset, at, scale)


## Keeps `preset` going on every camera with a shaker as the source `source`, at `level` (0 to 1,
## 0 lets it go). Call it every frame to follow a state (`hold_everywhere(&"engine", preset, 1.0
## if running else 0.0)`): the shaker eases to the level by the preset's `blend_speed`.
static func hold_everywhere(
	source: StringName, preset: ShakePreset, level := 1.0, at: Variant = null
) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return
	for node in tree.get_nodes_in_group(GROUP):
		(node as CameraShake).hold(source, preset, level, at)


func _init() -> void:
	_noise.seed = noise_seed
	_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_noise.frequency = 1.0


func _enter_tree() -> void:
	add_to_group(GROUP)


func _exit_tree() -> void:
	remove_from_group(GROUP)


func _process(delta: float) -> void:
	if auto_advance and not Engine.is_editor_hint():
		advance(delta)


## Plays `preset` once on this camera (see `shake`).
func add(preset: ShakePreset, at: Variant = null, scale := 1.0) -> void:
	if preset == null or not _listening():
		return
	var amount := preset.trauma * scale * preset.falloff(_distance_to(at))
	if amount <= 0.0:
		return
	var key := preset.get_instance_id()
	var shot: _Shot = _shots.get(key)
	if shot == null:
		shot = _Shot.new()
		shot.preset = preset
		_shots[key] = shot
	shot.trauma = minf(shot.trauma + amount, 1.0)
	_dirty = true


## Keeps `preset` going as `source` at `level` (see `hold_everywhere`).
func hold(source: StringName, preset: ShakePreset, level := 1.0, at: Variant = null) -> void:
	var held: _Held = _held.get(source)
	var target := 0.0
	if preset != null and _listening():
		target = clampf(level, 0.0, 1.0) * preset.falloff(_distance_to(at))
	if held == null:
		if target <= 0.0:
			return
		held = _Held.new()
		_held[source] = held
	held.preset = preset
	held.target = target


## Lets the held source `source` go: it dies down by its preset's `blend_speed`.
func release(source: StringName) -> void:
	var held: _Held = _held.get(source)
	if held != null:
		held.target = 0.0


## Stops everything at once.
func clear() -> void:
	_shots.clear()
	_held.clear()
	_rotation = Vector3.ZERO
	_offset = Vector2.ZERO
	_dirty = false


## Moves every shake on by `delta` seconds: trauma drains, held levels ease, rhythms turn.
func advance(delta: float) -> void:
	if _shots.is_empty() and _held.is_empty():
		return
	_dirty = true
	var finished: Array = []
	for key in _shots:
		var shot: _Shot = _shots[key]
		shot.time += delta
		shot.trauma -= delta / shot.preset.duration
		if shot.trauma <= 0.0:
			finished.append(key)
	for key in finished:
		_shots.erase(key)
	finished.clear()
	for source in _held:
		var held: _Held = _held[source]
		held.level = move_toward(held.level, held.target, held.preset.blend_speed * delta)
		if held.preset.wave == ShakePreset.Wave.SINE:
			held.phase = fmod(held.phase + TAU * held.preset.frequency * delta, TAU * 2.0)
		else:
			held.phase += delta
		if held.level <= 0.0 and held.target <= 0.0:
			finished.append(source)
	for source in finished:
		_held.erase(source)


## The turn of the view now in degrees: x pitch, y yaw, z roll. Zero when nothing shakes.
func rotation_degrees() -> Vector3:
	_refresh()
	return _rotation


## The slide of the picture now in metres: x sideways, y up (zero unless a preset sets
## `max_offset`).
func view_offset() -> Vector2:
	_refresh()
	return _offset


## True while anything is shaking or held.
func is_shaking() -> bool:
	return not _shots.is_empty() or not _held.is_empty()


## The level a held source is at now, 0 to 1 (0 when it is not running).
func level_of(source: StringName) -> float:
	var held: _Held = _held.get(source)
	return held.level if held != null else 0.0


## The trauma of `preset`'s one-shot now, 0 to 1 (0 when it is not running).
func trauma_of(preset: ShakePreset) -> float:
	var shot: _Shot = _shots.get(preset.get_instance_id())
	return shot.trauma if shot != null else 0.0


# The shaker is on and the global and own strengths are above zero.
func _listening() -> bool:
	return enabled and strength > 0.0 and camera_strength > 0.0


func _gain() -> float:
	return strength * camera_strength if enabled else 0.0


func _distance_to(at: Variant) -> float:
	if not (at is Vector3):
		return 0.0
	var from := reference
	if from == null and is_inside_tree():
		from = get_viewport().get_camera_3d()
	if from == null:
		return 0.0
	return from.global_position.distance_to(at as Vector3)


func _refresh() -> void:
	if not _dirty:
		return
	_dirty = false
	var turn := Vector3.ZERO
	var slide := Vector2.ZERO
	var gain := _gain()
	if gain > 0.0:
		for shot: _Shot in _shots.values():
			var preset := shot.preset
			var power := pow(shot.trauma, preset.exponent) * gain
			var at: float = shot.time * preset.frequency
			turn += preset.max_rotation * power * _noise3(at)
			slide += preset.max_offset * power * Vector2(_noise_at(at, 3), _noise_at(at, 4))
		for held: _Held in _held.values():
			var preset := held.preset
			var power := pow(smoothstep(0.0, 1.0, held.level), preset.exponent) * gain
			if preset.wave == ShakePreset.Wave.SINE:
				var phase := held.phase
				var wave := Vector3(sin(phase), sin(phase * 0.5), cos(phase * 0.5))
				turn += preset.max_rotation * power * wave
				slide += preset.max_offset * power * Vector2(cos(phase * 0.5), sin(phase))
			else:
				var at: float = held.phase * preset.frequency
				turn += preset.max_rotation * power * _noise3(at)
				slide += preset.max_offset * power * Vector2(_noise_at(at, 3), _noise_at(at, 4))
	_rotation = turn
	_offset = slide


func _noise3(at: float) -> Vector3:
	return Vector3(_noise_at(at, 0), _noise_at(at, 1), _noise_at(at, 2))


func _noise_at(at: float, line: int) -> float:
	return _noise.get_noise_2d(at, line * AXIS_SPACING)
