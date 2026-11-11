@tool
class_name Impacts
extends Node3D
## What a shot leaves where it lands: a mark on what it hit, an effect and a sound, picked by the
## kind of surface. One `Impacts` in a level serves every weapon: a `Projectile` (or anything
## else) reports a hit with `impact()` and this makes the rest. It joins the group `impacts`, so
## a projectile finds it without a path (`Impacts.find(self)`).
##
## A mark is a flat quad (`ImpactMark`) lifted off the surface a little and turned to its normal.
## It is a child of the body it hit, so it rides a crate that is pushed or a platform that moves
## and goes when the body is freed. Marks are made from a pool with a cap (`max_marks`): the
## oldest is taken for a new hit, and a mark that lives out `mark_lifetime` fades and is freed.
## No `Decal` is used: it does not draw in the Compatibility renderer, which the web build uses.
##
## What a surface does is an `ImpactSurface` node under `Surfaces`, with its own effect and
## sound as nodes you edit. Every number below is read when it is used, so a change while the
## game runs shows in the next hit (marks already on the walls keep the look they were made with).

## A hit made a mark, an effect or a sound.
signal impact_made(surface: ImpactSurface, collider: Object, point: Vector3, normal: Vector3)

## The group every `Impacts` joins while the game runs.
const GROUP := &"impacts"

@export_group("Marks")
## On: hits leave marks. Off: effects and sounds only.
@export var marks_enabled := true
## How many marks can be on the level at once. The oldest goes first. A lower number takes the
## extra ones off at once; zero leaves none.
@export_range(0, 512, 1, "or_greater") var max_marks := 64:
	set(value):
		max_marks = maxi(value, 0)
		_trim()
## How long a mark stays, in seconds. Zero keeps it until a newer one needs its place.
@export_range(0.0, 600.0, 0.5, "or_greater", "suffix:s") var mark_lifetime := 30.0
## How long the end of its life takes to fade it out. Longer than the lifetime fades it from the
## start.
@export_range(0.0, 60.0, 0.1, "or_greater", "suffix:s") var mark_fade_time := 4.0
## The material of the marks, unless the surface has its own. The default draws a bullet hole;
## change its colours or turn on its texture, or put in a shader of your own (it fades through the
## instance uniform `fade`: see `impact_mark.gdshader`).
@export var mark_material: Material
## How wide a mark is.
@export_range(0.01, 1.0, 0.005, "or_greater", "suffix:m") var mark_size := 0.12
## How much a mark's size varies from hit to hit, as a share of `mark_size`.
@export_range(0.0, 1.0, 0.01) var size_variation := 0.3
## On: each mark is turned a random way around its normal. Off: its up is the world's up.
@export var random_rotation := true
## How far a mark sits off the surface. It stops the surface from cutting through the mark; the
## material adds a little more with distance.
@export_range(0.0, 0.1, 0.001, "suffix:m") var surface_offset := 0.004
## The sequence the size and the turn are picked from. The same seed gives the same marks.
@export var random_seed := 1:
	set(value):
		random_seed = value
		_rng.seed = value

@export_group("Effects")
## On: a hit plays its surface's effect (sparks, dust).
@export var effects_enabled := true
## On: a hit plays its surface's sound.
@export var sounds_enabled := true

@export_group("Surfaces")
## The surface a hit gets when the body says nothing, or says a name no surface has.
@export var default_surface: ImpactSurface

var _rng := RandomNumberGenerator.new()
var _quad: QuadMesh
var _live: Array[ImpactMark] = []


func _init() -> void:
	_rng.seed = 1


func _enter_tree() -> void:
	if not Engine.is_editor_hint():
		add_to_group(GROUP)


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	# The first mark would build its material's programs at the first hit: the level's effect
	# emitter draws each mark material once while the level starts.
	var emitter := EffectEmitter.find(self)
	if emitter == null:
		return
	emitter.warm_material(mark_material)
	for surface: ImpactSurface in surfaces_by_name().values():
		emitter.warm_material(surface.mark_material)


func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	_prune()
	for mark in _live.duplicate():
		mark.age += delta
		if mark_lifetime > 0.0 and mark.age >= mark_lifetime:
			_retire(mark)
		else:
			mark.set_fade(_fade_at(mark.age))


## The `Impacts` of the level `from` is in (the first in the group), or null when there is none.
static func find(from: Node) -> Impacts:
	if from == null or not from.is_inside_tree():
		return null
	return from.get_tree().get_first_node_in_group(GROUP) as Impacts


## A hit on `collider` at `point`, the surface facing along `normal`: makes the mark, the effect
## and the sound its surface calls for, and returns that surface (null when there is none).
func impact(collider: Object, point: Vector3, normal: Vector3) -> ImpactSurface:
	var surface := surface_for(collider)
	if surface == null:
		return null
	if normal.length_squared() < 0.0001:
		normal = Vector3.UP
	normal = normal.normalized()
	if marks_enabled and surface.leaves_mark:
		_place_mark(surface, collider, point, normal)
	surface.play(point, normal, effects_enabled, sounds_enabled)
	impact_made.emit(surface, collider, point, normal)
	return surface


## The surface a body counts as: the first node from the body up to the root that has the metadata
## `surface`, or is in a group, named like a surface; the default surface when none does.
func surface_for(collider: Object) -> ImpactSurface:
	var surfaces := surfaces_by_name()
	var node := collider as Node
	while node != null:
		if node.has_meta(&"surface"):
			var named := StringName(str(node.get_meta(&"surface")))
			if surfaces.has(named):
				return surfaces[named]
		for group in node.get_groups():
			if surfaces.has(group):
				return surfaces[group]
		node = node.get_parent()
	return default_surface if default_surface != null else _first_surface()


## Every `ImpactSurface` under this node by its `surface_name`.
func surfaces_by_name() -> Dictionary:
	var found := {}
	for child in find_children("*", "ImpactSurface", true, false):
		found[(child as ImpactSurface).surface_name] = child
	return found


## The marks that are on the level now.
func marks() -> Array[ImpactMark]:
	_prune()
	return _live


## How many marks are on the level now.
func mark_count() -> int:
	_prune()
	return _live.size()


## Takes every mark off.
func clear_marks() -> void:
	for mark in _live.duplicate():
		_retire(mark)


## Takes off every mark on `body` or on a node under it (a ragdoll that gets up takes the marks
## off its bones).
func clear_marks_on(body: Node) -> void:
	if body == null:
		return
	_prune()
	for mark in _live.duplicate():
		if body.is_ancestor_of(mark):
			_retire(mark)


func _place_mark(surface: ImpactSurface, collider: Object, point: Vector3, normal: Vector3) -> void:
	var body := collider as Node3D
	# No mark on a character's capsule (it is not the body that is drawn): the effect and the
	# sound still play. A ragdoll bone takes one and carries it as the body moves; the game takes
	# it off when the body gets up (`clear_marks_on`).
	if body == null or body is CharacterBody3D or max_marks <= 0:
		return
	_prune()
	var mark: ImpactMark
	if _live.size() >= max_marks:
		mark = _live.pop_front()
		if mark.get_parent() != null:
			mark.get_parent().remove_child(mark)
	else:
		mark = _new_mark()
	mark.restart(surface.surface_name)
	mark.material_override = surface.mark_material if surface.mark_material else mark_material
	body.add_child(mark)
	var jitter := 1.0 + _rng.randf_range(-1.0, 1.0) * size_variation
	var width := mark_size * surface.mark_scale * jitter
	var world := Transform3D(
		_facing(normal).scaled_local(Vector3(width, width, 1.0)), point + normal * surface_offset
	)
	mark.transform = body.global_transform.affine_inverse() * world
	mark.reset_physics_interpolation()
	_live.append(mark)
	mark.set_fade(_fade_at(0.0))


# A basis whose +Z is `normal`, turned about it at random or with its up toward the world's up.
func _facing(normal: Vector3) -> Basis:
	if random_rotation:
		return Basis(Quaternion(Vector3.BACK, normal)).rotated(normal, _rng.randf() * TAU)
	var up := Vector3.UP if absf(normal.dot(Vector3.UP)) < 0.99 else Vector3.BACK
	return Basis.looking_at(-normal, up)


func _new_mark() -> ImpactMark:
	if _quad == null:
		_quad = QuadMesh.new()
		_quad.size = Vector2.ONE
	var mark := ImpactMark.new()
	mark.name = &"ImpactMark"
	mark.mesh = _quad
	mark.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mark


# How much of a mark of this age is left: whole until the last `mark_fade_time` seconds of its
# life, then falling to nothing.
func _fade_at(age: float) -> float:
	if mark_lifetime <= 0.0 or mark_fade_time <= 0.0:
		return 1.0
	return clampf((mark_lifetime - age) / mark_fade_time, 0.0, 1.0)


func _retire(mark: ImpactMark) -> void:
	_live.erase(mark)
	if is_instance_valid(mark):
		mark.queue_free()


# Forgets marks whose body was freed (they went with it).
func _prune() -> void:
	var kept: Array[ImpactMark] = []
	for mark in _live:
		if is_instance_valid(mark) and mark.is_inside_tree() and not mark.is_queued_for_deletion():
			kept.append(mark)
	_live = kept


func _trim() -> void:
	_prune()
	while _live.size() > max_marks:
		_retire(_live[0])


func _first_surface() -> ImpactSurface:
	var found := find_children("*", "ImpactSurface", true, false)
	return found[0] as ImpactSurface if not found.is_empty() else null


func _get_configuration_warnings() -> PackedStringArray:
	var warnings := PackedStringArray()
	if _first_surface() == null:
		warnings.append(
			"Add an `ImpactSurface` (under `Surfaces`): without one a hit shows nothing."
		)
	return warnings
