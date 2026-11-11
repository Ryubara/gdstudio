class_name AiNavigator
extends Node
## Moves an `AiCharacter` along the navigation map: the node in its `navigator` slot. It writes
## the controller's movement channel (`walk_direction`, `walk_strength`) and the moves on the way
## (`jump`, `crouch`, `sprint`), and the body walks, climbs steps, crouches, slides and vaults
## with its own moves; nobody is ever moved by hand.
##
## - `go_to(point, speed_scale)` walks to a point, `follow(node, band)` keeps within `band` of a
##   node, `stop()` stands; `arrived` and `failed(reason)` say how it ended.
## - One API over two backends: SERVER asks `NavigationServer3D.query_path` (no node, the same
##   answer on every machine), AGENT a `NavigationAgent3D` (for its RVO). Both ask on a timer of
##   `repath_seconds` with a phase of their own, never more often, and only when the director's
##   shared `AiBudget` allows; the body-ray check and the headroom probe take rays from it too.
## - The rules Deadnight learnt: goals snapped to open ground of the layers, a route kept unless a
##   new one is clearly shorter, an unreachable goal asked once more with no search limit and then
##   remembered for 5 s, no query before the map's first iteration, the server's map off async
##   iterations, heights from the path, and a new path checked as the body would walk it.
## - Stuck (a commanded speed over 1 m/s and under 0.25 m/s of progress along the path for 0.5 s)
##   climbs `AiStuckLadder`: sidestep, repath from the mesh to a moved goal, a jump where the level
##   allows one, drop the goal for 10 s, walk back along the breadcrumbs, report. A path that ends
##   3 m or more short of a target 12 m or more away is `stranded`; moving the character elsewhere
##   is the director's choice, never the navigator's.
## - A navigation link moves nobody: at a link's start it emits `link_reached` and crosses it with
##   a sprint and a jump (or walks off a drop), or, with `auto_traverse_links` off, waits for
##   `finish_link()` from the task that does the crossing.
##
## The character calls `navigate(seconds)` before each step of its body, with the time since the
## last one, so a far character stepped every 4th tick walks the same path as far.

## The goal was reached (or, following, the node is within the band).
signal arrived
## The goal was given up (`Failure`); `refusal` says why.
signal failed(reason: int)
## The path reached the start of a navigation link: `link` (a `NavigationLink3D`, or null), from
## its start to its end.
signal link_reached(link: Node, from: Vector3, to: Vector3)
## The path ends `gap` metres short of a target 12 m or more away: the director may move it.
signal stranded(gap: float)
## A new path was taken.
signal path_changed

enum Backend { SERVER, AGENT }
enum Failure { NO_PATH, UNREACHABLE, STUCK, BLOCKED }
enum NavClass { SMALL, NORMAL, LARGE }
enum Mode { IDLE, GO_TO, FOLLOW }

## The failure names, for the debug overlay and messages.
const FAILURE_NAMES: Array[String] = ["no path", "unreachable", "stuck", "blocked"]
## Seconds an unreachable goal is remembered (asked about again only after).
const UNREACHABLE_SECONDS := 5.0
## Seconds a goal given up on as stuck is refused.
const DROP_SECONDS := 10.0
## A path ending this far short (metres) of a target this far away is stranded.
const STRANDED_GAP := 3.0
const STRANDED_TARGET := 12.0
## A path that ends this near the goal (metres, on the ground) reaches it.
const END_SLACK := 1.0
## How far (metres) the stuck ladder's repath moves the goal at most.
const JITTER := 1.0
## Breadcrumbs: one every this many metres walked with progress, the last this many kept.
const CRUMB_SPACING := 1.0
const CRUMBS := 8
## A path found blocked on this many checks in a row is given up.
const BLOCKS_TO_FAIL := 3
## A corner sharper than this (radians) restarts the stuck window: the body turns there.
const SHARP_TURN := deg_to_rad(100.0)
## A new path whose length left differs from the old one's by more than this (metres) is another
## route: the stuck window starts over.
const REROUTE := 1.0
## A climb steeper than this (rise over run) is held to `max_climb_speed`.
const STEEP := 0.15
## Seconds the jump is held, and the crouch after the headroom probe saw a low ceiling.
const JUMP_HOLD := 0.25
const CROUCH_HOLD := 1.0
## How near (metres) a `Vaultable` on the path must be for the jump that vaults it.
const VAULT_REACH := 1.2
## Following: metres past the band before it walks again.
const FOLLOW_SLACK := 0.5

static var _spawned := 0
static var _class_maps: Dictionary[int, RID] = {}

## The character it moves; empty: its parent.
@export var character: AiCharacter

@export_group("Path")
## SERVER: `NavigationServer3D` queries and its own steering, no node (the default: the same cost
## as AGENT, repeatable). AGENT: a `NavigationAgent3D` child, for its RVO avoidance.
@export var backend := Backend.SERVER
## Seconds between two path queries (each character on a phase of its own); 0: the profile's
## `repath_seconds` (0.25 s).
@export_range(0.0, 10.0, 0.05, "suffix:s") var repath_seconds := 0.0
## How near (metres, on the ground) the goal counts as reached.
@export_range(0.05, 5.0, 0.05, "suffix:m") var arrive_distance := 0.5
## How near (metres) a point of the path counts as passed.
@export_range(0.05, 5.0, 0.05, "suffix:m") var path_desired_distance := 0.6
## Points nearer than this (metres) are skipped when choosing where to steer.
@export_range(0.0, 5.0, 0.05, "suffix:m") var look_ahead := 0.5
## Which map it walks: a size class registered with `register_class_map()`; NORMAL (and a class
## with no map) walks the world's own.
@export var nav_class := NavClass.NORMAL
## The navigation layers its paths and goals use.
@export_flags_3d_navigation var navigation_layers := 1
## The most polygons a query searches; an unreachable goal is asked once more with no limit.
@export_range(0, 65536) var search_max_polygons := 4096
## The fastest it climbs a steep stretch of path (m/s); 0: as fast as it walks.
@export_range(0.0, 10.0, 0.05, "suffix:m/s") var max_climb_speed := 0.0

@export_group("Moves")
## Crosses a navigation link itself (a sprint and a jump, or a walk off a drop). Off: it waits
## at the link for `finish_link()` from the task that crosses it.
@export var auto_traverse_links := true
## Metres of each new path checked with rays as the body would walk it.
@export_range(0.0, 50.0, 0.5, "suffix:m") var check_reach := 12.0
## Looks for a ceiling too low to stand under ahead, and crouches (a slide, at a sprint).
@export var headroom_check := true

@export_group("Avoidance")
## OFF, SEPARATION (a push from the characters near it) or RVO (the server's avoidance).
@export var avoidance := AiNavAvoidance.Mode.OFF
## The push's reach, and twice the RVO radius (metres).
@export_range(0.2, 5.0, 0.05, "suffix:m") var avoidance_radius := 1.2

@export_group("Debug")
## Draws the path and the point it steers to, and writes the stuck rung and the reason a goal was
## refused into the character's overlay. Costs nothing while off.
@export var debug := false:
	set(value):
		debug = value
		_update_debug_draw()

## The path being walked.
var path := AiNavPath.new()
## The stuck detector, with the seconds walked and stuck.
var watch := AiStuckWatch.new()
## The stuck ladder.
var ladder := AiStuckLadder.new()
## Path queries asked since the start.
var path_queries := 0
## The last failure (`Failure`), or -1.
var last_failure := -1
## Why the last goal was refused or given up, for the overlay.
var refusal := ""
## What it is doing (`Mode`).
var mode := Mode.IDLE
## The point asked for, and where it walks for it (on open ground).
var target := Vector3.INF
var goal := Vector3.INF
## The share of a full run asked for (above 1: a sprint).
var speed_scale := 1.0
## Following: the node and the band.
var follow_node: Node3D
var follow_band := 2.0

var _query: AiNavQuery
var _fresh := AiNavPath.new()
var _avoid := AiNavAvoidance.new()
var _check := AiPathCheck.new()
var _unreachable := AiRouteRules.GoalMemory.new()
var _dropped := AiRouteRules.GoalMemory.new()
var _rng := RandomNumberGenerator.new()
var _clock := 0.0
var _since_query := INF
var _phase := 0.0
var _first_since_goal := true
var _want_query := false
var _raised_next := false
var _jitter_next := false
var _from_mesh_next := false
var _arrived := false
var _on_link := -1
var _link_waiting := false
var _link_jumped := false
var _link_airborne := false
var _crumbs: Array[Vector3] = []
var _crumb_index := -1
var _blocks := 0
var _jump_for := 0.0
var _crouch_for := 0.0
var _vaulted_at := Vector3.INF
var _stranded_told := false
var _others: Array[Node] = []
var _steer_at := Vector3.INF
var _draw: AiNavDebug
var _map_ready := false


## Gives size class `nav_class_wanted` its own map (a big creature's mesh, baked for its radius);
## an invalid RID takes it back to the world's map.
static func register_class_map(nav_class_wanted: NavClass, map: RID) -> void:
	if map.is_valid():
		_class_maps[nav_class_wanted] = map
	else:
		_class_maps.erase(nav_class_wanted)


func _ready() -> void:
	if character == null:
		character = get_parent() as AiCharacter
	_phase = fmod(_spawned * 0.618034, 1.0)
	_rng.seed = 967 + _spawned
	_spawned += 1
	if character == null:
		push_warning("AiNavigator %s: no AiCharacter to move." % name)
		return
	if backend == Backend.AGENT:
		_query = AiNavAgentQuery.new(character)
	else:
		_query = AiNavQuery.new()
	_check.mask = character.collision_mask
	_update_debug_draw()


func _exit_tree() -> void:
	_avoid.stop()
	if _query != null:
		_query.release()


## The map it walks.
func navigation_map() -> RID:
	if _class_maps.has(nav_class):
		return _class_maps[nav_class]
	return character.get_world_3d().navigation_map if character != null else RID()


## Walks to `point` at `speed` (the share of a full run, 0 to 1; above 1 sprints). False, and
## `failed` at once, when the goal is one it gave up on or could not reach a moment ago.
func go_to(point: Vector3, speed := 1.0) -> bool:
	if _dropped.holds(point, _clock):
		_refuse(Failure.STUCK, "given up on a moment ago")
		return false
	if _unreachable.holds(point, _clock):
		_refuse(Failure.UNREACHABLE, "unreachable a moment ago")
		return false
	_begin(Mode.GO_TO, point, speed)
	return true


## Keeps within `band` metres of `node`, walking at `speed`.
func follow(node: Node3D, band := 2.0, speed := 1.0) -> void:
	follow_node = node
	follow_band = band
	_begin(Mode.FOLLOW, node.global_position, speed)


## Stands still and forgets the goal.
func stop() -> void:
	mode = Mode.IDLE
	_arrived = false
	path.clear()
	watch.clear()
	ladder.reset()
	_link_waiting = false
	_on_link = -1
	_release()


## True once the goal was reached (or, following, while within the band).
func is_arrived() -> bool:
	return _arrived


## True while it has a goal.
func is_active() -> bool:
	return mode != Mode.IDLE


## Called by the task that crossed the link `link_reached` named: the walk goes on from its end.
func finish_link() -> void:
	_link_waiting = false
	_on_link = -1


## One step of the walk, `seconds` after the last (called by the character before its body
## steps).
func navigate(seconds: float) -> void:
	if character == null or _query == null:
		return
	_clock += seconds
	_since_query += seconds
	_jump_for = maxf(_jump_for - seconds, 0.0)
	_crouch_for = maxf(_crouch_for - seconds, 0.0)
	if mode == Mode.IDLE or character.is_dead():
		_release()
		return
	var map := navigation_map()
	# A map that has not taken its first iteration answers nothing: wait, never a frame count.
	if NavigationServer3D.map_get_iteration_id(map) == 0:
		_release()
		return
	if not _map_ready:
		_map_ready = true
		NavigationServer3D.map_set_use_async_iterations(map, false)
		_start_avoidance(map)
	if mode == Mode.FOLLOW and not _follow_wants_walk():
		_release()
		return
	_maybe_query(map)
	if mode == Mode.IDLE:
		return
	if not _check.is_done(path):
		_check.run(path, character, character.budget)
		if _check.is_done(path):
			_judge_check()
			if mode == Mode.IDLE:
				return
	_walk(seconds)
	if debug and _draw != null:
		_draw.draw(path, character.global_position, _steer_at, goal)


## The overlay's line: what it does, the stuck rung, the reason a goal was refused.
func debug_text() -> String:
	var line := ""
	match mode:
		Mode.GO_TO:
			line = "go to %.1f m" % path.left(character.global_position)
		Mode.FOLLOW:
			line = "follow"
		_:
			line = "arrived" if _arrived else "idle"
	if ladder.is_climbing():
		line += " · stuck: %s" % ladder.rung_name()
	if _link_waiting or _on_link >= 0:
		line += " · link"
	if refusal != "":
		line += "\n%s" % refusal
	return line


func _begin(new_mode: Mode, point: Vector3, speed: float) -> void:
	mode = new_mode
	target = point
	goal = Vector3.INF
	speed_scale = speed
	refusal = ""
	_arrived = false
	_want_query = true
	_first_since_goal = true
	_raised_next = false
	_stranded_told = false
	_blocks = 0
	_link_waiting = false
	_on_link = -1
	path.clear()
	watch.clear()
	ladder.reset()


func _repath_interval() -> float:
	if repath_seconds > 0.0:
		return repath_seconds
	return character.profile.repath_seconds if character.profile != null else 0.25


# Asks for a path when one is due, never sooner than `repath_seconds` after the last, and only
# when the shared budget allows (a refusal tries again at the next step).
func _maybe_query(map: RID) -> void:
	var interval := _repath_interval()
	if _since_query < interval:
		return
	# On a link the body is off the mesh: a path asked from there starts back at the link.
	if _link_waiting or _on_link >= 0:
		return
	if character.budget != null and not character.budget.take_path():
		return
	_query_now(map, interval)


func _query_now(map: RID, interval: float) -> void:
	path_queries += 1
	# Each character repaths on its own phase: the first answer after a goal waits a share of
	# the interval more, so a crowd given goals on one tick spreads its queries.
	_since_query = -_phase * interval if _first_since_goal else 0.0
	_first_since_goal = false
	_want_query = false
	_others = get_tree().get_nodes_in_group(AiCharacter.GROUP)
	var from := character.global_position
	if _from_mesh_next:
		from = NavigationServer3D.map_get_closest_point(map, from)
		_from_mesh_next = false
	if mode == Mode.FOLLOW or not goal.is_finite():
		goal = AiRouteRules.snap_goal(map, target, from, navigation_layers)
	if not goal.is_finite():
		_unreachable.remember(target, _clock + UNREACHABLE_SECONDS)
		_fail(Failure.UNREACHABLE, "no open ground near the goal")
		return
	var to := goal
	if _jitter_next:
		var offset := Vector3(_rng.randf_range(-1.0, 1.0), 0.0, _rng.randf_range(-1.0, 1.0))
		to = NavigationServer3D.map_get_closest_point(map, goal + offset * JITTER)
		_jitter_next = false
	var limit := 0 if _raised_next else search_max_polygons
	_query.ask(map, from, to, navigation_layers, limit, _fresh)
	if _fresh.points.is_empty():
		_fail(Failure.NO_PATH, "the map gave no path")
		return
	var gap := AiNavPath.flat(_fresh.end() - goal).length()
	if gap > END_SLACK:
		if mode == Mode.GO_TO:
			if not _raised_next:
				# Asked once more with no search limit, at the next slot of the timer.
				_raised_next = true
				_want_query = true
				return
			_unreachable.remember(target, _clock + UNREACHABLE_SECONDS)
			_fail(Failure.UNREACHABLE, "the path ends %.1f m short" % gap)
			return
		var away := AiNavPath.flat(target - from).length()
		if not _stranded_told and away >= STRANDED_TARGET and gap >= STRANDED_GAP:
			_stranded_told = true
			stranded.emit(gap)
	_raised_next = false
	var at := character.global_position
	if (
		path.has_points()
		and not path.is_finished()
		and AiRouteRules.keeps_route(path.left(at), path.end(), _fresh.length(), target)
	):
		return
	var changed := _differs(_fresh, path)
	# Another route (not the same one asked again): the stuck window starts over on it.
	var rerouted := absf(_fresh.left(at) - path.left(at)) > REROUTE or not path.has_points()
	var swap := path
	path = _fresh
	_fresh = swap
	if changed or _check.blocked_at >= 0:
		_check.reach = check_reach
		_check.begin()
		_vaulted_at = Vector3.INF
	if rerouted:
		watch.rebase(path.left(at))
	if headroom_check:
		_probe_headroom()
	path_changed.emit()


# True when two paths differ by more than half a metre at a point (or in their count).
func _differs(one: AiNavPath, other: AiNavPath) -> bool:
	if one.points.size() != other.points.size():
		return true
	for index in one.points.size():
		if one.points[index].distance_squared_to(other.points[index]) > 0.25:
			return true
	return false


func _judge_check() -> void:
	if _check.blocked_at < 0:
		_blocks = 0
		return
	_blocks += 1
	if _blocks >= BLOCKS_TO_FAIL:
		_fail(Failure.BLOCKED, "blocked by %s" % _check.blocker)


func _walk(seconds: float) -> void:
	var controller := character.ai_controller()
	if controller == null:
		return
	var at := character.global_position
	if _link_waiting or not path.has_points():
		_release()
		return
	if ladder.rung >= AiStuckLadder.Rung.DROP_GOAL:
		_walk_back(seconds, controller, at)
		return
	var passed := path.advance(at, path_desired_distance, arrive_distance)
	if passed > 0:
		if path.turn_at(path.index - 1) > SHARP_TURN:
			watch.rebase(path.left(at))
		var link_start := path.index - 1
		if path.link_at(link_start) != 0 and _on_link != link_start:
			_begin_link(link_start)
			if _link_waiting:
				_release()
				return
	var end := path.end(at)
	var near_end := (
		AiNavPath.flat(end - at).length() < arrive_distance
		and absf(end.y - at.y) < AiNavPath.HEIGHT_REACH
	)
	if mode == Mode.GO_TO and (path.is_finished() or near_end) and _on_link < 0:
		_arrive()
		return
	var steer := path.points[_on_link + 1] if _on_link >= 0 else path.steer_point(at, look_ahead)
	_steer_at = steer
	var wish := AiNavPath.flat(steer - at).normalized()
	var strength := clampf(speed_scale, 0.0, 1.0)
	var sprint := speed_scale > 1.0 or _on_link >= 0 or _heading_to_link(at)
	strength = _climb_cap(strength, at, steer)
	if ladder.rung == AiStuckLadder.Rung.SIDESTEP and ladder.rung_seconds < ladder.sidestep_seconds:
		wish = wish.cross(Vector3.UP) * ladder.side
	var speed := _commanded_speed(strength, sprint)
	wish = _avoid.steer(character, wish, speed, _others).normalized()
	if near_end and mode == Mode.FOLLOW:
		wish = Vector3.ZERO
	_link_moves(at, wish)
	_vault_moves(at)
	controller.walk_direction = wish
	controller.walk_strength = 1.0 if sprint else strength
	controller.sprint = sprint
	controller.jump = _jump_for > 0.0
	controller.crouch = _crouch_for > 0.0 or not character.has_room_to_stand()
	_judge_stuck(seconds, speed if wish != Vector3.ZERO else 0.0, at)


func _judge_stuck(seconds: float, speed: float, at: Vector3) -> void:
	var left := path.left(at)
	if watch.sample(seconds, speed, left):
		ladder.start()
		_on_rung()
		return
	if not ladder.is_climbing():
		_drop_crumb(at)
		return
	if not watch.stuck:
		ladder.reset()
		return
	if ladder.tick(seconds):
		ladder.next()
		_on_rung()


# What a rung does as it begins.
func _on_rung() -> void:
	match ladder.rung:
		AiStuckLadder.Rung.REPATH:
			_from_mesh_next = true
			_jitter_next = true
			_want_query = true
		AiStuckLadder.Rung.JUMP:
			if _may_jump():
				_jump_for = JUMP_HOLD
			else:
				ladder.next()
				_on_rung()
		AiStuckLadder.Rung.DROP_GOAL:
			_dropped.remember(target, _clock + DROP_SECONDS)
			ladder.next()
			_crumb_index = _crumbs.size() - 1
		AiStuckLadder.Rung.REPORT:
			_fail(Failure.STUCK, "stuck %.1f s, gave up" % watch.episode_seconds)


# A jump is tried only where the level allows one: a `Vaultable` on the path near, or a link.
func _may_jump() -> bool:
	var at := character.global_position
	if _check.vault_at.is_finite() and AiNavPath.flat(_check.vault_at - at).length() < 2.0:
		return true
	return _heading_to_link(at) or _on_link >= 0


# The breadcrumb rungs: walk back along where it came from, then report.
func _walk_back(seconds: float, controller: AiController, at: Vector3) -> void:
	while _crumb_index >= 0 and AiNavPath.flat(_crumbs[_crumb_index] - at).length() < 0.5:
		_crumb_index -= 1
	var done := ladder.tick(seconds) or _crumb_index < 0
	if done and ladder.rung == AiStuckLadder.Rung.BREADCRUMB:
		ladder.next()
		_on_rung()
		return
	if _crumb_index < 0:
		_release()
		return
	controller.walk_direction = AiNavPath.flat(_crumbs[_crumb_index] - at).normalized()
	controller.walk_strength = clampf(speed_scale, 0.3, 1.0)
	controller.sprint = false
	controller.jump = false


func _drop_crumb(at: Vector3) -> void:
	if not _crumbs.is_empty() and _crumbs[-1].distance_to(at) < CRUMB_SPACING:
		return
	_crumbs.append(at)
	if _crumbs.size() > CRUMBS:
		_crumbs.remove_at(0)


func _heading_to_link(at: Vector3) -> bool:
	if path.is_finished() or path.link_at(path.index) == 0:
		return false
	return AiNavPath.flat(path.points[path.index] - at).length() < 4.0


func _begin_link(link_start: int) -> void:
	var link := instance_from_id(path.link_at(link_start)) as Node
	var from := path.points[link_start]
	var to := path.points[mini(link_start + 1, path.points.size() - 1)]
	_on_link = link_start
	_link_jumped = false
	_link_airborne = false
	link_reached.emit(link, from, to)
	if not auto_traverse_links:
		_link_waiting = true


# Crossing a link: a drop is walked off; a gap is jumped where the floor ends ahead. The link is
# crossed once the body lands past its start, or reaches its end.
func _link_moves(at: Vector3, wish: Vector3) -> void:
	if _on_link < 0:
		return
	var from := path.points[_on_link]
	var to := path.points[_on_link + 1]
	if AiNavPath.flat(to - at).length() < path_desired_distance or path.index > _on_link + 1:
		_on_link = -1
		return
	if not character.is_on_floor():
		_link_airborne = true
		return
	if _link_airborne:
		_on_link = -1
		return
	var drop := to.y < from.y - 0.4
	if drop or _link_jumped or wish == Vector3.ZERO:
		return
	if not _floor_ahead(at, wish):
		_jump_for = JUMP_HOLD
		_link_jumped = true


func _vault_moves(at: Vector3) -> void:
	var spot := _check.vault_at
	if not spot.is_finite() or spot == _vaulted_at:
		return
	if AiNavPath.flat(spot - at).length() < VAULT_REACH:
		_jump_for = JUMP_HOLD
		_vaulted_at = spot


# True when there is floor under the front of the body a step ahead (one ray from the budget; a
# refused ray says yes, so the jump waits a tick).
func _floor_ahead(at: Vector3, direction: Vector3) -> bool:
	if character.budget != null and not character.budget.take_ray():
		return true
	var ahead := at + direction * (character.tuning.radius + 0.15)
	var query := PhysicsRayQueryParameters3D.create(
		ahead + Vector3.UP * 0.3, ahead + Vector3.DOWN * 0.6, character.collision_mask
	)
	query.exclude = [character.get_rid()]
	return not character.get_world_3d().direct_space_state.intersect_ray(query).is_empty()


# A ceiling ahead too low to stand under, with room at the knees: crouch for a while (two rays).
func _probe_headroom() -> void:
	if path.is_finished():
		return
	var budget := character.budget
	if budget != null and (budget.rays + 2 > budget.rays_per_tick):
		return
	var at := character.global_position
	var ahead := AiNavPath.flat(path.steer_point(at, look_ahead) - at)
	if ahead.length_squared() < 0.0001:
		return
	ahead = ahead.normalized() * 1.0
	var space := character.get_world_3d().direct_space_state
	var head := Vector3.UP * (character.tuning.height - 0.1)
	var knee := Vector3.UP * AiPathCheck.KNEE
	if budget != null:
		budget.take_ray()
		budget.take_ray()
	var high := PhysicsRayQueryParameters3D.create(
		at + head, at + head + ahead, character.collision_mask, [character.get_rid()]
	)
	var low := PhysicsRayQueryParameters3D.create(
		at + knee, at + knee + ahead, character.collision_mask, [character.get_rid()]
	)
	if not space.intersect_ray(high).is_empty() and space.intersect_ray(low).is_empty():
		_crouch_for = CROUCH_HOLD


func _climb_cap(strength: float, at: Vector3, steer: Vector3) -> float:
	if max_climb_speed <= 0.0:
		return strength
	var run := AiNavPath.flat(steer - at).length()
	if run < 0.01 or (steer.y - at.y) / run < STEEP:
		return strength
	return minf(strength, max_climb_speed / maxf(character.tuning.run_speed, 0.01))


# The speed (m/s) the body is asked to go: what `Character` makes of the push.
func _commanded_speed(strength: float, sprint: bool) -> float:
	var tuning := character.tuning
	if character.crouching:
		return tuning.crouch_speed * maxf(strength, tuning.least_walk_share)
	if sprint:
		return tuning.sprint_speed
	if strength < tuning.walk_below_push:
		return tuning.walk_speed * maxf(strength, tuning.least_walk_share)
	return tuning.run_speed * strength


# Following: true while the node is out of the band (with a slack before it walks again).
func _follow_wants_walk() -> bool:
	if not is_instance_valid(follow_node):
		stop()
		return false
	target = follow_node.global_position
	var away := AiNavPath.flat(target - character.global_position).length()
	if away <= follow_band:
		if not _arrived:
			_arrived = true
			watch.clear()
			ladder.reset()
			arrived.emit()
		return false
	if _arrived and away <= follow_band + FOLLOW_SLACK:
		return false
	if _arrived:
		_arrived = false
		_want_query = true
	return true


func _arrive() -> void:
	mode = Mode.IDLE
	_arrived = true
	watch.clear()
	ladder.reset()
	_release()
	arrived.emit()


func _fail(reason: Failure, why: String) -> void:
	mode = Mode.IDLE
	_arrived = false
	path.clear()
	watch.clear()
	ladder.reset()
	_on_link = -1
	_release()
	_refuse(reason, why)


func _refuse(reason: Failure, why: String) -> void:
	last_failure = reason
	refusal = "%s: %s" % [FAILURE_NAMES[reason], why]
	failed.emit(reason)


func _release() -> void:
	var controller := character.ai_controller() if character != null else null
	if controller == null:
		return
	controller.walk_direction = Vector3.ZERO
	controller.sprint = false
	controller.jump = _jump_for > 0.0
	controller.crouch = false


func _start_avoidance(map: RID) -> void:
	_avoid.mode = avoidance
	_avoid.radius = avoidance_radius
	var agent := (_query as AiNavAgentQuery).agent if _query is AiNavAgentQuery else null
	_avoid.start(map, character, agent, character.tuning.sprint_speed)


func _update_debug_draw() -> void:
	if not is_inside_tree():
		return
	if debug and _draw == null:
		_draw = AiNavDebug.new()
		add_child(_draw)
	elif not debug and _draw != null:
		_draw.queue_free()
		_draw = null
