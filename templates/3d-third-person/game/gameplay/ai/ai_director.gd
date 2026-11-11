class_name AiDirector
extends Node
## The one node that budgets every AI character of a level (`world/world.tscn` holds it; the
## characters find it through the group `ai_director`). Each physics tick it:
##
## - resets the shared `budget` (rays, path queries and thinks a tick, from the inspector);
## - puts each character in a **tier** by its distance to the nearest player's body, checked every
##   8th tick on the character's own slot, with a margin before it drops a tier and a cap on how
##   many are at the Full tier at once;
## - runs each character's **think** at its profile's rate for its tier, on a phase of its own
##   chosen where the fewest thinks already fall, so the thinks spread over the ticks;
## - **steps** each character's body: every tick at the Full tier, every `reduced_step_ticks`
##   at Reduced and every `dormant_step_ticks` at Dormant, with the missed time handed on so a far
##   character walks as far.
##
## It gives a character its `tier` and its `budget` and nothing else; what a think decides is the
## character's. `last_step_usec` is what the whole step cost on the last tick.

enum Tier { FULL, REDUCED, DORMANT }

## The group the director joins.
const GROUP := &"ai_director"
## Ticks between two tier checks of one character.
const TIER_PERIOD := 8
## Ticks the think schedule looks ahead (an interval longer than this is cut to it).
const RING := 1024
## Below this speed (m/s) a body counts as standing still.
const REST_SPEED := 0.01

## The tier names, for the debug overlay and logs.
const TIER_NAMES: Array[String] = ["Full", "Reduced", "Dormant"]

@export_group("Population")
## The most characters it manages in a browser (a browser in a match sets it for everyone); one
## more is refused and stands frozen, with a warning.
@export_range(0, 1000) var web_cap := 40
## The most characters it manages on the desktop and on a server.
@export_range(0, 4000) var desktop_cap := 120
## The most characters at the Full tier at once in a browser; the next nearest wait at Reduced.
@export_range(0, 1000) var web_full_cap := 12
## The most characters at the Full tier at once on the desktop and on a server.
@export_range(0, 4000) var desktop_full_cap := 60
## The group of the bodies the tiers measure from (the players).
@export var player_group := &"player"

@export_group("Budget a tick")
## Sight rays all characters together may cast in one physics tick.
@export_range(0, 256) var rays_per_tick := 8
## Path queries all characters together may make in one physics tick.
@export_range(0, 256) var paths_per_tick := 4
## Thinks run in one physics tick; one over waits for the next tick.
@export_range(1, 256) var thinks_per_tick := 12

@export_group("Steps")
## A Reduced character's body is stepped every this many ticks, with the missed time.
@export_range(1, 30) var reduced_step_ticks := 4
## A Dormant character's body is stepped every this many ticks, with the missed time.
@export_range(1, 60) var dormant_step_ticks := 6
## A character at rest (standing still on a floor that does not move, asking for nothing, or
## dead) is stepped every this many ticks at most, whatever its tier; 1 steps it every tick.
@export_range(1, 30) var rest_step_ticks := 3

@export_group("Animation")
## Animates the characters less often where nobody would see it (far, off-screen, Dormant); each
## character it manages is handed to it. Empty: every character animates every frame.
@export var animation_throttle: AiAnimationThrottle

## The work the characters share this tick.
var budget := AiBudget.new()
## Physics ticks since the director started.
var tick := 0
## Bodies stepped since the director started (a count for tests and benches).
var body_steps := 0
## Microseconds the last tick's step (tiers, thinks and bodies) took.
var last_step_usec := 0

var _entries: Array[Entry] = []
var _think_load := PackedInt32Array()
var _viewers: Array[Node3D] = []
var _full_count := 0
var _next_slot := 0
var _still := PlayerCommand.new()


## A managed character and its place in the schedule.
class Entry:
	var character: AiCharacter
	var slot := 0
	var next_think := -1
	var last_think := 0
	var last_step := 0
	var distance := INF


## The director of the tree, or null.
static func find(tree: SceneTree) -> AiDirector:
	return tree.get_first_node_in_group(GROUP) as AiDirector if tree != null else null


## The tier for a character at `distance` from the nearest player that is at `current` now:
## nearer than `full_range` is Full, nearer than `reduced_range` is Reduced, farther Dormant, and
## a character keeps a nearer tier until it is `tier_margin` past that tier's range.
static func tier_for(current: int, distance: float, profile: AiProfile) -> int:
	var margin := profile.tier_margin
	if (
		distance < profile.full_range
		or (current == Tier.FULL and distance < profile.full_range + margin)
	):
		return Tier.FULL
	var keep := current <= Tier.REDUCED
	if distance < profile.reduced_range or (keep and distance < profile.reduced_range + margin):
		return Tier.REDUCED
	return Tier.DORMANT


func _init() -> void:
	_think_load.resize(RING)


func _ready() -> void:
	add_to_group(GROUP)
	_refresh_viewers()
	for node in get_tree().get_nodes_in_group(AiCharacter.GROUP):
		register(node as AiCharacter)


## The most characters it manages here (`web_cap` in a browser, else `desktop_cap`).
func population_cap() -> int:
	return web_cap if OS.has_feature("web") else desktop_cap


## The most characters at the Full tier at once here.
func full_cap() -> int:
	return web_full_cap if OS.has_feature("web") else desktop_full_cap


## How many characters it manages.
func count() -> int:
	return _entries.size()


## How many characters are at `tier`.
func count_at(tier_wanted: int) -> int:
	var found := 0
	for entry in _entries:
		if entry.character.tier == tier_wanted:
			found += 1
	return found


## Takes `character` over: its own physics processing stops and the director steps it. Returns
## false (and the character stands frozen) when the population cap is reached.
func register(character: AiCharacter) -> bool:
	if character == null or _index_of(character) >= 0:
		return character != null
	if _entries.size() >= population_cap():
		push_warning(
			"AiDirector: %s refused, the cap of %d is reached." % [character.name, population_cap()]
		)
		character.set_physics_process(false)
		return false
	var entry := Entry.new()
	entry.character = character
	entry.slot = _next_slot
	_next_slot += 1
	entry.last_think = tick
	entry.last_step = tick
	_entries.append(entry)
	character.director = self
	character.budget = budget
	character.set_physics_process(false)
	character.tier = Tier.DORMANT
	_update_tier(entry)
	_schedule(entry)
	if animation_throttle != null:
		animation_throttle.add(character)
	return true


## Lets `character` go: it steps itself again and is no longer counted.
func unregister(character: AiCharacter) -> void:
	var index := _index_of(character)
	if index < 0:
		return
	var entry := _entries[index]
	_unschedule(entry)
	if character.tier == Tier.FULL:
		_full_count -= 1
	_entries.remove_at(index)
	character.director = null
	character.budget = null
	character.set_physics_process(true)
	if animation_throttle != null and is_instance_valid(animation_throttle):
		animation_throttle.remove(character)


func _physics_process(delta: float) -> void:
	var start := Time.get_ticks_usec()
	tick += 1
	budget.rays_per_tick = rays_per_tick
	budget.paths_per_tick = paths_per_tick
	budget.thinks_per_tick = thinks_per_tick
	budget.reset()
	if tick % TIER_PERIOD == 0:
		_refresh_viewers()
	# Starts one further along each tick, so a think the budget put off is not put off again.
	var size := _entries.size()
	for offset in size:
		var entry := _entries[(tick + offset) % size]
		if (tick + entry.slot) % TIER_PERIOD == 0:
			_update_tier(entry)
		if entry.next_think >= 0 and tick >= entry.next_think:
			_think(entry, delta)
		_step(entry, delta)
	last_step_usec = Time.get_ticks_usec() - start


func _think(entry: Entry, delta: float) -> void:
	_think_load[entry.next_think % RING] -= 1
	if not budget.take_think():
		entry.next_think = tick + 1
		_think_load[entry.next_think % RING] += 1
		return
	var character := entry.character
	var seconds := (tick - entry.last_think) * delta
	entry.last_think = tick
	var interval := _think_interval(entry)
	if interval <= 0:
		entry.next_think = -1
	else:
		entry.next_think += interval
		if entry.next_think <= tick:
			entry.next_think = tick + interval
		_think_load[entry.next_think % RING] += 1
	character.think(seconds)


func _step(entry: Entry, delta: float) -> void:
	var every := 1
	match entry.character.tier:
		Tier.REDUCED:
			every = reduced_step_ticks
		Tier.DORMANT:
			every = dormant_step_ticks
	if every < rest_step_ticks and _at_rest(entry.character):
		every = rest_step_ticks
	var missed := tick - entry.last_step
	if missed < every and (tick + entry.slot) % every != 0:
		return
	if missed <= 0:
		return
	missed = mini(missed, maxi(reduced_step_ticks, dormant_step_ticks))
	entry.last_step = tick
	body_steps += 1
	var character := entry.character
	var command := (
		character.controller.sample() if character.controller != null else _still_command()
	)
	character.step(command, delta * missed)


# True when stepping the body less often changes nothing: it is dead, or it stands on a floor that
# does not move, still, and its controller asks for nothing.
func _at_rest(character: AiCharacter) -> bool:
	if character.is_dead():
		return true
	var controller := character.controller as AiController
	return (
		controller != null
		and controller.is_still()
		and character.velocity.length_squared() < REST_SPEED * REST_SPEED
		and character.is_on_floor()
		and character.get_platform_velocity() == Vector3.ZERO
	)


# Ticks between two thinks at the character's tier, from its profile now (so a change applies at
# the next think); 0 when it does not think at this tier.
func _think_interval(entry: Entry) -> int:
	var rate := entry.character.profile.think_rate_at(entry.character.tier)
	if rate <= 0.0:
		return 0
	return clampi(roundi(Engine.physics_ticks_per_second / rate), 1, RING - 1)


# Puts the next think on the tick of the coming interval where the fewest thinks fall.
func _schedule(entry: Entry) -> void:
	_unschedule(entry)
	var interval := _think_interval(entry)
	if interval <= 0:
		return
	var best := tick + 1
	var least := 1 << 30
	for offset in range(1, interval + 1):
		var taken := _think_load[(tick + offset) % RING]
		if taken < least:
			least = taken
			best = tick + offset
	entry.next_think = best
	_think_load[best % RING] += 1


func _unschedule(entry: Entry) -> void:
	if entry.next_think >= 0:
		_think_load[entry.next_think % RING] -= 1
		entry.next_think = -1


func _update_tier(entry: Entry) -> void:
	var character := entry.character
	entry.distance = _nearest_viewer(character.global_position)
	var wanted := tier_for(character.tier, entry.distance, character.profile)
	if wanted == Tier.FULL and character.tier != Tier.FULL and _full_count >= full_cap():
		var farthest := _farthest_full()
		if farthest != null and farthest.distance > entry.distance:
			_set_tier(farthest, Tier.REDUCED)
		else:
			wanted = Tier.REDUCED
	if wanted != character.tier:
		_set_tier(entry, wanted)
	elif entry.next_think < 0 and _think_interval(entry) > 0:
		_schedule(entry)


func _set_tier(entry: Entry, wanted: int) -> void:
	var character := entry.character
	if character.tier == Tier.FULL:
		_full_count -= 1
	if wanted == Tier.FULL:
		_full_count += 1
	character.set_tier(wanted)
	_schedule(entry)


func _farthest_full() -> Entry:
	var found: Entry = null
	for entry in _entries:
		if entry.character.tier == Tier.FULL and (found == null or entry.distance > found.distance):
			found = entry
	return found


func _nearest_viewer(spot: Vector3) -> float:
	var nearest := INF
	for viewer in _viewers:
		if is_instance_valid(viewer):
			nearest = minf(nearest, viewer.global_position.distance_squared_to(spot))
	return sqrt(nearest)


func _refresh_viewers() -> void:
	_viewers.clear()
	for node in get_tree().get_nodes_in_group(player_group):
		if node is Node3D:
			_viewers.append(node)


func _index_of(character: AiCharacter) -> int:
	for index in _entries.size():
		if _entries[index].character == character:
			return index
	return -1


# What a character with no controller steps: nothing asked.
func _still_command() -> PlayerCommand:
	_still.clear()
	return _still
