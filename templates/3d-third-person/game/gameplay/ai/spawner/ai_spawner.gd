class_name AiSpawner
extends Node3D
## Keeps `count` AI characters of `scene` alive at the spawn `markers`, from a pool (`AiPool`):
## the characters are made before they are needed (when the level loads, or with `wake_range` one
## a tick as a player comes within `PREWARM_MARGIN` of it) and never again, and a death is
## answered by a spawn of a pooled one `respawn_delay` seconds later. A body lies in its ragdoll
## until it settles (or `corpse_seconds`), at most `max_corpses` at once, then goes back to the
## pool.
##
## Placed by hand in a level (the AI section holds one per kind) and tuned in the inspector. It
## wires each character it spawns to the level: the brain's `patrol_route`, its `leader` (the
## first node of `leader_group`, an ally's player) and the overlay. With `wake_range` it spawns
## only once a player comes that near, so a far part of the map costs nothing until somebody goes
## there.
##
## It spawns only where the AI runs: offline, and on a game server only with `on_server` (a client
## draws what the server sends). Everything runs on the physics clock, so a run repeats.
##
## Docs: the kit's `docs/engines/godot/third-person/ai-characters.md`.

## A character came into the level (a new one or one from the pool).
signal spawned(character: AiCharacter)
## A body went back to the pool.
signal released(character: AiCharacter)

## Metres around a marker another living character must keep for it to be picked.
const MARKER_CLEAR := 1.5
## Physics ticks between two looks for a player within `wake_range`.
const WAKE_CHECK_TICKS := 15
## Metres beyond `wake_range` at which the pool starts making its characters, one a tick, so
## they are ready when the player arrives and a level nobody goes near holds none.
const PREWARM_MARGIN := 10.0

@export_group("Spawn")
## The character it spawns (an inherited `ai_character.tscn`: `characters/enemy_grunt.tscn`).
@export var scene: PackedScene
## How many it keeps alive at once.
@export_range(0, 64) var count := 3
## Where they spawn, in turn (a marker with a living character near it is skipped); each faces
## the marker's -Z. Empty: the spawner itself.
@export var markers: Array[Node3D] = []
## Seconds after a death until another one spawns; below 0 the dead are not replaced.
@export_range(-1.0, 600.0, 0.5, "suffix:s") var respawn_delay := 10.0
## The most it spawns in all (0: no limit).
@export_range(0, 100000) var cap := 0
## Off: it spawns nothing more (the living stay); on again, it fills up to `count`.
@export var enabled := true:
	set(value):
		enabled = value
		if enabled and is_node_ready():
			_fill()

@export_group("Waking")
## It spawns its characters once the nearest body of `player_group` is this near (metres from
## the spawner); 0 spawns them at once.
@export_range(0.0, 1000.0, 0.5, "suffix:m") var wake_range := 0.0
## The group of the bodies that wake it (the players).
@export var player_group := &"player"

@export_group("Wiring")
## The patrol route the characters walk (`AiMarker.route`); empty: any patrol marker. A route with
## no markers makes a guard hold its spawn.
@export var patrol_route := &""
## The characters follow the first node of this group (an ally's player); empty: nobody.
@export var leader_group := &""
## Shows each character's debug overlay.
@export var debug := false:
	set(value):
		debug = value
		for character in alive:
			character.debug = value

@export_group("Bodies")
## The most bodies it leaves lying at once; the oldest goes back to the pool first.
@export_range(0, 32) var max_corpses := 4
## The longest a body lies (a death that played its clip has no ragdoll to settle).
@export_range(0.0, 600.0, 0.5, "suffix:s") var corpse_seconds := 20.0
## Seconds a body lies on after its ragdoll settled.
@export_range(0.0, 60.0, 0.5, "suffix:s") var settled_linger := 2.0

@export_group("Network")
## Spawns on a game server too (the server's characters reach the clients through the AI's
## replication); off: offline play only. A client of a remote server never spawns.
@export var on_server := false

## The characters alive now.
var alive: Array[AiCharacter] = []
## The bodies lying now, oldest first.
var corpses: Array[AiCharacter] = []
## How many it spawned in all.
var spawned_total := 0
## True once a player came within `wake_range` (at once without one).
var awake := false

var _pool: AiPool
var _clock := 0.0
var _died_at: Dictionary[int, float] = {}
var _settled_at: Dictionary[int, float] = {}
var _due: PackedFloat64Array = PackedFloat64Array()
var _next_marker := 0
var _ticks := 0
var _runs := false
var _prewarming := false


## True when AI characters are spawned in this tree: offline play, or a game server with
## `on_server` (never a client of a remote server). `args` are the command line's.
static func spawns_here(tree: SceneTree, server_too := false, args := NetArgs.new()) -> bool:
	if args.has("connect"):
		return false
	var root := tree.current_scene if tree != null else null
	if root != null:
		for child in root.get_children():
			if child is NetClient:
				return false
	if args.is_server() or root is NetServer:
		return server_too
	return true


func _ready() -> void:
	_pool = AiPool.new(scene)
	_runs = spawns_here(get_tree(), on_server) and AiAuthority.runs_here(self)
	set_physics_process(_runs)
	if not _runs or scene == null:
		return
	awake = wake_range <= 0.0
	if awake:
		_pool.prewarm(_pool_size(), 0, self)
	_fill()


# The parked characters are out of the tree: freed with the spawner.
func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE and _pool != null:
		_pool.clear()


func _physics_process(delta: float) -> void:
	# A client joined a server since (`AiAuthority.hand_over`): the AI is the server's now.
	if not AiAuthority.runs_here(self):
		_runs = false
		set_physics_process(false)
		_pool.clear()
		return
	_clock += delta
	_ticks += 1
	if _prewarming:
		_prewarming = _pool.prewarm(_pool_size(), alive.size() + corpses.size(), self, 1)
	if not awake and _ticks % WAKE_CHECK_TICKS == 0:
		if enabled and not _prewarming and _player_within(wake_range + PREWARM_MARGIN):
			_prewarming = true
		if _player_within(wake_range):
			awake = true
			_fill()
	_tend_corpses()
	if not _due.is_empty() and _due[0] <= _clock:
		_due.remove_at(0)
		_fill()


## The pool it spawns from (for a test or a tool).
func pool() -> AiPool:
	return _pool


## Spawns one at the next free marker now; null when there is none to spawn (off, at `cap`, or
## no scene).
func spawn_one() -> AiCharacter:
	if not enabled or scene == null or (cap > 0 and spawned_total >= cap):
		return null
	var character := _pool.take()
	if character == null and not corpses.is_empty():
		_release(corpses[0])
		character = _pool.take()
	if character == null:
		return null
	var place := _next_place()
	if not character.died.is_connected(_on_died):
		character.died.connect(_on_died.bind(character))
	add_child(character)
	character.teleport(place.origin, _heading_of(place.basis))
	_restock(character)
	character.restart_mind()
	_wire(character)
	alive.append(character)
	spawned_total += 1
	AiSensePool.forget()
	spawned.emit(character)
	return character


## Sends a lying body back to the pool now.
func release(character: AiCharacter) -> void:
	if corpses.has(character):
		_release(character)


func _fill() -> void:
	if not _runs or not awake or not enabled:
		return
	while alive.size() + _due.size() < count:
		if spawn_one() == null:
			return


func _pool_size() -> int:
	return count + max_corpses


func _wire(character: AiCharacter) -> void:
	character.debug = debug
	var mind := character.brain as AiBrain
	if mind == null:
		return
	mind.patrol_route = patrol_route
	mind.leader = null
	if leader_group != &"":
		mind.leader = get_tree().get_first_node_in_group(leader_group) as Node3D


# A spawn again starts with the weapon it starts with, full.
func _restock(character: AiCharacter) -> void:
	var loadout := character.loadout
	if loadout != null and loadout.held_slot() != loadout.start_slot:
		loadout.equip_now(loadout.start_slot)
	var weapon := character.weapon
	if weapon != null and weapon.definition != null and weapon.definition.magazine_size > 0:
		weapon.set_ammo(weapon.definition.magazine_size, weapon.definition.start_reserve)


func _on_died(character: AiCharacter) -> void:
	if not alive.has(character):
		return
	alive.erase(character)
	corpses.append(character)
	_died_at[character.get_instance_id()] = _clock
	if respawn_delay >= 0.0:
		_due.append(_clock + respawn_delay)
	while corpses.size() > max_corpses:
		_release(corpses[0])


func _tend_corpses() -> void:
	for index in range(corpses.size() - 1, -1, -1):
		var body := corpses[index]
		var id := body.get_instance_id()
		var lying := _clock - float(_died_at.get(id, _clock))
		var ragdoll := body.ragdoll_body as CharacterRagdoll
		if ragdoll != null and ragdoll.is_settled() and not _settled_at.has(id):
			_settled_at[id] = _clock
		var settled_for := _clock - float(_settled_at.get(id, INF))
		if lying >= corpse_seconds or settled_for >= settled_linger:
			_release(body)


func _release(character: AiCharacter) -> void:
	corpses.erase(character)
	var id := character.get_instance_id()
	_died_at.erase(id)
	_settled_at.erase(id)
	AiSenses.forget_everywhere(character)
	if character.is_inside_tree():
		character.revive_at(character.global_position)
		character.restart_mind()
		remove_child(character)
	_pool.park(character)
	AiSensePool.forget()
	released.emit(character)


# The next marker in turn that no living character stands near (the next one when all are).
func _next_place() -> Transform3D:
	if markers.is_empty():
		return global_transform
	var size := markers.size()
	for offset in size:
		var marker := markers[(_next_marker + offset) % size]
		if marker == null or not marker.is_inside_tree():
			continue
		if _is_clear(marker.global_position):
			_next_marker = (_next_marker + offset + 1) % size
			return marker.global_transform
	var fallback := markers[_next_marker % size]
	_next_marker = (_next_marker + 1) % size
	return fallback.global_transform if fallback != null else global_transform


func _is_clear(spot: Vector3) -> bool:
	for character in alive:
		if character.global_position.distance_to(spot) < MARKER_CLEAR:
			return false
	return true


# The heading `Character.teleport` takes (0 faces +Z) for a marker facing its -Z.
func _heading_of(basis_of: Basis) -> float:
	var forward := -basis_of.z
	return atan2(forward.x, forward.z)


func _player_within(reach: float) -> bool:
	var at := global_position
	for node in get_tree().get_nodes_in_group(player_group):
		var body := node as Node3D
		if body != null and body.global_position.distance_to(at) <= reach:
			return true
	return false
