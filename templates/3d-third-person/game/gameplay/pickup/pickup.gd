@tool
class_name Pickup
extends Area3D
## Something to collect: a coin, a key, a health pack. It spins and bobs, and when a character (a
## `CharacterBody3D` on the Collision > Mask layers: Characters, so the area never even hears of a
## wall, the floor or a crate beside it) touches it, `collected` says who took what. The area sits
## on the Sensors layer. `characters_only` checks the class as well, for a mask that lists more.
## It does nothing else: the game decides what an item means (a body with a
## `collect(item_id, amount)` method, like `Player`, is also told). It works on its own and can
## come back after a while.
##
## Its look is two nodes of `pickup.tscn`, `Visual` (the mesh) and `Shape` (what a body touches),
## so open the scene to restyle it. `tint` and `item_size` follow the inspector live. Its sound is
## the `Sound` node (an `AudioStreamPlayer3D`: volume, bus and distance are its own); a pickup
## with no `respawn_time` waits for the sound to end before it goes.
##
## `Visual` can be any `Node3D` (a weapon's model under it: `WeaponPickup`); it spins and bobs about
## the height it has in the scene. A script that extends this one decides what a body is given by
## overriding `_give()`.

## A body took the pickup. `item_id` and `amount` are the inspector's values.
signal collected(collector: Node3D, item_id: StringName, amount: int)
## The pickup came back after `respawn_time`.
signal respawned

@export_group("Item")
## What the item is called; the game reads this to decide what it gives.
@export var item_id: StringName = &"coin"
## How many of it one pickup is worth.
@export_range(1, 999, 1, "or_greater") var amount := 1
## The shape's colour.
@export var tint := Color(1.0, 0.78, 0.2):
	set(value):
		tint = value
		_update_look()

@export_group("Collector")
## Only a `CharacterBody3D` can take it. The mask (Characters) already keeps the level and props
## out; this keeps them out too when the mask lists their layers (a game with its own layers, or
## one where the level shares layer 1), where a coin set against a wall would be taken at the
## start. Off lets any body on the Collision > Mask layers take it.
@export var characters_only := true

@export_group("Look")
## How wide the item is.
@export_range(0.1, 3.0, 0.05, "suffix:m") var item_size := 0.5:
	set(value):
		item_size = value
		_update_look()
## Turn speed. Zero keeps it still.
@export_range(0.0, 720.0, 1.0, "suffix:deg/s") var spin_speed := 120.0
## How far it rises and falls. Zero keeps it still.
@export_range(0.0, 1.0, 0.01, "suffix:m") var bob_height := 0.12
## Seconds for one rise and fall.
@export_range(0.2, 10.0, 0.1, "suffix:s") var bob_period := 1.6

@export_group("Sound")
## The sounds a pickup plays when it is taken, one of them each time (the coin has four).
@export var sounds: Array[AudioStream] = []
## How much the pitch varies from one pickup to the next, as a share (0.05 is 5 percent either way).
@export_range(0.0, 0.5, 0.01) var pitch_variation := 0.04

@export_group("Respawn")
## Comes back this long after it was taken. Zero collects it once and removes it.
@export_range(0.0, 600.0, 0.5, "or_greater", "suffix:s") var respawn_time := 0.0

var _phase := 0.0
# The `Visual` node, found once (it was looked up by its unique name every frame).
var _visual_node: Node3D
# The height `Visual` has in the scene: it bobs about it.
var _rest_height := 0.0
var _hidden_for := -1.0
var _rng := RandomNumberGenerator.new()
var _last_sound := -1


func _ready() -> void:
	_rng.seed = 1
	_update_look()
	if _visual() != null:
		_rest_height = _visual().position.y
	if Engine.is_editor_hint():
		set_process(false)
		return
	body_entered.connect(_on_body_entered)


func _process(delta: float) -> void:
	_phase += delta
	if _visual_node == null:
		_visual_node = _visual()
	var visual := _visual_node
	visual.rotation.y = deg_to_rad(spin_speed) * _phase
	visual.position.y = _rest_height + sin(TAU * _phase / bob_period) * bob_height
	if _hidden_for >= 0.0:
		_hidden_for += delta
		if respawn_time > 0.0 and _hidden_for >= respawn_time:
			_show_again()


## True while the item can be taken.
func is_available() -> bool:
	return monitoring and _visual().visible


func _get_configuration_warnings() -> PackedStringArray:
	var warnings := PackedStringArray()
	if _visual() == null or _shape() == null:
		warnings.append("The scene needs a `Visual` (a Node3D) and a `Shape` (CollisionShape3D).")
	return warnings


func _visual() -> Node3D:
	return get_node_or_null("%Visual") as Node3D


func _shape() -> CollisionShape3D:
	return get_node_or_null("%Shape") as CollisionShape3D


func _on_body_entered(body: Node3D) -> void:
	if not is_available() or (characters_only and not body is CharacterBody3D):
		return
	if not _give(body):
		return
	_hide_now()
	var length := _play_sound()
	if respawn_time <= 0.0:
		if length > 0.0:
			get_tree().create_timer(length).timeout.connect(queue_free)
		else:
			queue_free()


# Gives `body` the item and says so; false leaves the pickup where it is (the body could not take
# it). A script that extends this one gives something else here (a weapon).
func _give(body: Node3D) -> bool:
	collected.emit(body, item_id, amount)
	# A body that keeps count (a `Character`) is told too, so no wiring is needed to carry a coin.
	if body.has_method(&"collect"):
		body.call(&"collect", item_id, amount)
	return true


# Plays one of the sounds and returns how long it lasts (zero when there is nothing to play).
func _play_sound() -> float:
	var player := get_node_or_null("%Sound") as AudioStreamPlayer3D
	if player == null or sounds.is_empty():
		return 0.0
	var pick := _rng.randi() % sounds.size()
	if sounds.size() > 1 and pick == _last_sound:
		pick = (pick + 1) % sounds.size()
	_last_sound = pick
	player.stream = sounds[pick]
	player.pitch_scale = 1.0 + _rng.randf_range(-pitch_variation, pitch_variation)
	player.play()
	return sounds[pick].get_length() / player.pitch_scale + 0.05


func _hide_now() -> void:
	_set_shown(false)
	set_deferred("monitoring", false)
	_hidden_for = 0.0


func _show_again() -> void:
	_set_shown(true)
	monitoring = true
	_hidden_for = -1.0
	respawned.emit()


# Shows or hides what the pickup looks like while it is away (a script that extends this one hides
# its glow too).
func _set_shown(shown: bool) -> void:
	_visual().visible = shown


# Puts `tint` and `item_size` on the nodes' own resources (each pickup has its own copies:
# they are local to the scene).
func _update_look() -> void:
	var visual := _visual()
	var shape := _shape()
	if visual == null or shape == null:
		return
	var gem := (visual as MeshInstance3D).mesh as SphereMesh if visual is MeshInstance3D else null
	if gem == null:
		return
	gem.radius = item_size / 2.0
	gem.height = item_size
	var paint := (visual as MeshInstance3D).material_override as StandardMaterial3D
	paint.albedo_color = tint
	paint.emission = tint
	(shape.shape as SphereShape3D).radius = maxf(item_size, 0.5) * 0.75
