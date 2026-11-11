class_name AiNoise
extends Node
## The level's noise board (a node of `world/world.tscn`, group `ai_noise`): what can be heard.
## Anything makes a noise with `AiNoise.emit(node, kind, position, loudness, source)` (the
## `AiNoiseMaker` of every character does for its footsteps, shots and impacts); the board keeps
## the last `capacity` noises for `keep_seconds`, each with the radius its kind has in `radii`
## times its loudness. A listener (`AiSenses`) reads the noises made since its last think and
## tests the radius, never the world: one ray only for a noise past `occlusion` of the radius.
##
## It runs where the AI runs (the authority): on a client of a remote server `emit` does nothing
## (`runs_here()`), since only the state the senses cause is ever sent.

## The group the board joins, which `find` reads.
const GROUP := &"ai_noise"
## The kinds the template makes.
const FOOTSTEP := &"footstep"
const LANDING := &"landing"
const SHOT := &"shot"
const IMPACT := &"impact"
const EXPLOSION := &"explosion"

static var _runs_here := -1

## Metres a noise of each kind carries at loudness 1, for a listener of the reference hearing; a
## kind not in the table carries `default_radius`.
@export var radii: Dictionary[StringName, float] = {
	FOOTSTEP: 9.0,
	LANDING: 12.0,
	SHOT: 45.0,
	IMPACT: 14.0,
	EXPLOSION: 70.0,
}
## Metres a noise of a kind the table does not name carries at loudness 1.
@export_range(0.0, 500.0, 0.5, "suffix:m") var default_radius := 10.0
## The share of a noise's radius heard through anything (walls included); past it, to the edge,
## a listener needs a clear line (one budgeted ray), else the noise is muffled away.
@export_range(0.0, 1.0, 0.01) var occlusion := 0.5
## The `AiProfile.hearing_range` the radii are written for: a profile with twice this hears every
## noise twice as far.
@export_range(1.0, 200.0, 0.5, "suffix:m") var reference_hearing := 30.0
## Seconds a noise stays on the board: longer than the slowest think that should hear it.
@export_range(0.1, 10.0, 0.05, "suffix:s") var keep_seconds := 1.0
## The most noises it keeps; an older one is dropped for a newer.
@export_range(4, 1024) var capacity := 128

@export_group("Debug")
## Draws each noise as a ring of its radius while it is on the board. Off by default.
@export var show_noises := false:
	set(value):
		show_noises = value
		set_process(show_noises)
		if not show_noises and _view != null:
			_view.visible = false

## The serial of the newest noise (0: none yet). Serials only grow.
var newest := 0
## The serials of the noises each faction made (by the faction id of the maker's member when it
## made them), oldest first, so a listener walks only the factions it cares about
## (`serials_since`); read only. A list may hold serials already dropped from the board.
var by_faction: Dictionary[StringName, Array] = {}
## The serials of the noises made by nothing in a faction (no source, or one with no member).
var unowned: Array[int] = []

var _ring: Array[AiNoiseRecord] = []
# The capacity the ring was made with (an edit of `capacity` applies to a board made again).
var _size := 0
var _view: MeshInstance3D


## The board of `node`'s tree, or null.
static func find(node: Node) -> AiNoise:
	if node == null or not node.is_inside_tree():
		return null
	return node.get_tree().get_first_node_in_group(GROUP) as AiNoise


## Makes a noise of `kind` at `position`, `loudness` times its kind's radius, by `source` (null
## when nothing perceivable made it), on the board of `from`'s tree. Returns false when there is
## no board or the AI does not run here.
static func emit(
	from: Node, kind: StringName, position: Vector3, loudness := 1.0, source: Node3D = null
) -> bool:
	if not runs_here():
		return false
	var board := find(from)
	if board == null:
		return false
	board.post(kind, position, loudness, source)
	return true


## False on a client of a remote server (started with `--connect`, or a page with `?connect=`):
## the senses and the noises run on the authority only. Read once.
static func runs_here() -> bool:
	if _runs_here < 0:
		_runs_here = 0 if NetArgs.new().has("connect") else 1
	return _runs_here == 1


func _enter_tree() -> void:
	add_to_group(GROUP)


func _ready() -> void:
	set_process(show_noises)


func _process(_delta: float) -> void:
	_draw()


## Puts a noise on the board and returns it.
func post(
	kind: StringName, position: Vector3, loudness := 1.0, source: Node3D = null
) -> AiNoiseRecord:
	if _ring.is_empty():
		_size = capacity
	var noise: AiNoiseRecord
	if _ring.size() < _size:
		noise = AiNoiseRecord.new()
		_ring.append(noise)
	else:
		noise = _ring[newest % _size]
	newest += 1
	noise.serial = newest
	noise.kind = kind
	noise.position = position
	noise.loudness = maxf(loudness, 0.0)
	noise.radius = radius_of(kind) * noise.loudness
	noise.set_source(source)
	noise.frame = Engine.get_physics_frames()
	_index(noise)
	return noise


## Adds to `into` the serials of `serials` (one list of `by_faction`, or `unowned`) from `first` on,
## oldest first. Returns true when it added any.
func serials_since(serials: Array, first: int, into: Array[int]) -> bool:
	var count := serials.size()
	if count == 0 or serials[count - 1] < first:
		return false
	var start := count - 1
	while start > 0 and serials[start - 1] >= first:
		start -= 1
	for index in range(start, count):
		into.append(serials[index])
	return true


# Files the noise under its maker's faction; a list twice the board's size keeps its newest half
# (the board holds no more than its size).
func _index(noise: AiNoiseRecord) -> void:
	var serials: Array = unowned
	if noise.member != null:
		serials = by_faction.get(noise.faction, null)
		if serials == null:
			var fresh: Array[int] = []
			serials = fresh
			by_faction[noise.faction] = serials
	serials.append(noise.serial)
	if serials.size() >= _size * 2:
		serials.assign(serials.slice(serials.size() - _size))


## Metres a noise of `kind` carries at loudness 1.
func radius_of(kind: StringName) -> float:
	return radii.get(kind, default_radius)


## The noise with `serial`, or null when it was dropped or is older than `keep_seconds`.
func noise_at(serial: int) -> AiNoiseRecord:
	var noise := record(serial)
	if noise == null or noise.frame < first_kept_frame():
		return null
	return noise


## The noise with `serial` whatever its age, or null when it was dropped (a listener checks the
## age itself against `first_kept_frame()`, read once).
func record(serial: int) -> AiNoiseRecord:
	if serial <= 0 or serial > newest or serial <= newest - _ring.size():
		return null
	var noise := _ring[(serial - 1) % _size]
	return noise if noise.serial == serial else null


## The physics frame of the oldest noise still kept by age.
func first_kept_frame() -> int:
	return Engine.get_physics_frames() - int(keep_seconds * Engine.physics_ticks_per_second)


## The oldest serial still on the board (newest + 1 when it is empty).
func oldest() -> int:
	return newest - _ring.size() + 1


func _draw() -> void:
	if _view == null:
		_view = MeshInstance3D.new()
		_view.top_level = true
		_view.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_view.mesh = ImmediateMesh.new()
		_view.material_override = AiSensesView.ground_material()
		add_child(_view)
	_view.visible = true
	var mesh := _view.mesh as ImmediateMesh
	mesh.clear_surfaces()
	var drew := false
	for serial in range(oldest(), newest + 1):
		var noise := noise_at(serial)
		if noise == null or noise.radius <= 0.0:
			continue
		if not drew:
			mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
			drew = true
		var at := noise.position + Vector3.UP * 0.06
		AiSensesView.add_ring(mesh, at, noise.radius, 0.06, Color(0.4, 0.7, 1.0, 0.8), 48)
	if drew:
		mesh.surface_end()
