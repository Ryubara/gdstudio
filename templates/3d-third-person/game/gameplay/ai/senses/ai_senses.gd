class_name AiSenses
extends Node
## What an AI character can know, cheaply and fairly: sight, hearing, touch and what its allies
## tell it, turned into `beliefs` (an `AiBeliefs`) that the brain reads instead of the world. A
## child of `ai_character.tscn`, set as the character's `senses` slot; the character runs
## `sense(seconds)` at the start of each think (the director's think tick, never every physics
## tick), and a blow is felt at once.
##
## - **Sight**, cheapest first: the distance squared (`sight_range`, `lose_sight_range` for a
##   thing already seen, `near_radius` for one at arm's reach), then the relationship (only what
##   the character cares about: Hostile, Unfriendly up to `care_up_to`), then the cone (from the
##   way it looks or aims, not the body; none within `near_radius`), then at most
##   `max_rays_per_think` rays, each taken from the director's shared `AiBudget`, oldest result
##   first. A ray result is trusted for `ray_fresh_seconds`. A Dormant character does not look.
## - **Hearing**: the noises on the level's `AiNoise` board since the last think, each heard
##   within its radius (scaled by the profile's `hearing_range`); one ray only for a noise past
##   the board's `occlusion` share of the radius.
## - **Touch**: a hit (`Character.took_hit`) is believed at once, with awareness 1.
## - **Team**: a thing noticed is told to the allies within `share_radius` after `share_delay`;
##   each ally passes one telling on at most once.
##
## **Awareness** of each thing rises at `1 / time_to_notice` while it is seen (slower far, to the
## side, still, crouched or lying down, and for an Unfriendly one), from the first clear ray; at
## `suspicious_at` it says `suspicious`, at 1 `alerted` (noticed), and `reaction_time` later the
## thing is believed (`entity_noticed`): the brain may act on it. Unseen, it falls; a memory is
## forgotten `memory_seconds` after it was last perceived (`entity_lost`). The highest awareness
## feeds the character's `situation`.
##
## It runs on the authority only (`authority_only`): a client of a remote server senses nothing,
## and only the state the senses cause is sent.

## A thing's awareness reached `suspicious_at`.
signal suspicious(entity: Node3D, belief: AiBelief)
## A thing was noticed (awareness 1); the reaction delay starts.
signal alerted(entity: Node3D, belief: AiBelief)
## A thing is believed: noticed and the reaction delay passed (or felt, at once).
signal entity_noticed(entity: Node3D, belief: AiBelief)
## A remembered thing was forgotten (`memory_seconds` after it was last perceived, or gone).
signal entity_lost(entity_id: int, belief: AiBelief)
## A noise was heard (`source` null: something, not someone).
signal heard(kind: StringName, position: Vector3, source: Node3D)

## The result of a line test.
enum Line { CLEAR, BLOCKED, REFUSED }

## The group every senses node joins (the team share and the witnesses read it).
const GROUP := &"ai_senses"

static var _next_share := 0
static var _group_frame := -1
static var _group_cache: Dictionary[StringName, Array] = {}

@export_group("Senses")
## Looks: the cone, the near radius, the rays.
@export var sight := true
## Hears the noises of the level's `AiNoise` board.
@export var hearing := true
## Feels a hit at once.
@export var touch := true
## Tells allies what it noticed and listens to theirs.
@export var team := true

@export_group("Targets")
## The groups whose members it may perceive; the relationships say which of them it cares about.
@export var target_groups: Array[StringName] = [&"player", &"ai_characters"]
## The friendliest band (`AiRelations.Band`) it still perceives: Unfriendly takes Hostile and
## Unfriendly things, Hostile only enemies. Nothing past it is looked at, heard or remembered.
@export var care_up_to: AiRelations.Band = AiRelations.Band.UNFRIENDLY
## What blocks sight (and muffles a far noise): the world and props, never characters or their
## hit zones.
@export_flags_3d_physics var sight_mask := PhysicsLayers.CAMERA_MASK
## Where it sees from (the head); empty: 1.55 m above the character's feet.
@export var eye: Node3D
## The share of a target's height the sight ray aims at (its head and shoulders).
@export_range(0.1, 1.0, 0.01) var target_height_share := 0.85

@export_group("Awareness")
## The share of the full rate at the edge of `sight_range` (1 at the eye).
@export_range(0.0, 1.0, 0.01) var far_share := 0.3
## The share of the full rate at the edge of the cone (1 straight ahead).
@export_range(0.0, 1.0, 0.01) var side_share := 0.5
## The share of the full rate for a thing standing still (1 from the profile's `walk_speed` up).
@export_range(0.0, 1.0, 0.01) var still_share := 0.7
## The share for a crouched thing.
@export_range(0.0, 1.0, 0.01) var crouch_share := 0.6
## The share for a thing lying down.
@export_range(0.0, 1.0, 0.01) var prone_share := 0.35
## The share for an Unfriendly thing (a Hostile one is 1).
@export_range(0.0, 1.0, 0.01) var unfriendly_share := 0.5
## Seconds a glimpse (seen, not yet noticed) takes to fall from awareness 1 to 0 out of sight.
@export_range(0.1, 60.0, 0.1, "suffix:s") var glimpse_seconds := 3.0
## Awareness a heard noise adds at its source (times how near it was, 0 at the radius), on top
## of `suspicious_at`.
@export_range(0.0, 1.0, 0.01) var heard_gain := 0.5
## Seconds a ray's answer is trusted before it must be cast again.
@export_range(0.0, 2.0, 0.01, "suffix:s") var ray_fresh_seconds := 0.3

@export_group("Network")
## Senses nothing on a client of a remote server: the AI runs on the authority.
@export var authority_only := true

@export_group("Debug")
## Draws the cone, the near and hearing radii, a line to each belief and the awareness bars.
@export var show_view := false:
	set(value):
		show_view = value
		if view != null:
			view.visible = value
## The node that draws it (an `AiSensesView`, a child in `ai_character.tscn`).
@export var view: AiSensesView

## What it believes.
var beliefs := AiBeliefs.new()
## Senses runs since it started.
var thinks := 0
## Rays cast since it started (sight and muffled noises).
var rays_cast := 0
## Rays the last `sense` cast (never over the profile's `max_rays_per_think`).
var last_rays := 0
## Tellings it took from allies (one per telling, however many allies passed it on).
var shares_received := 0
## Microseconds the last `sense` took.
var last_sense_usec := 0

var _character: AiCharacter
var _member: AiFactionMember
var _factions: AiFactions
var _board: AiNoise
var _query := PhysicsRayQueryParameters3D.new()
var _rays_left := 0
var _heard_serial := 0
var _ray_at: Dictionary[int, float] = {}
var _ray_clear: Dictionary[int, bool] = {}
var _looked: Dictionary[int, bool] = {}
var _visible: Dictionary[int, bool] = {}
var _candidates: Array[Node3D] = []
var _candidate_bands := PackedInt32Array()
var _candidate_near: Array[bool] = []
var _outbox: Array[Share] = []
var _share_keys: Dictionary[int, bool] = {}


## A telling on its way to the allies.
class Share:
	var key := 0
	var member: AiFactionMember
	var position := Vector3.ZERO
	var velocity := Vector3.ZERO
	var due := 0.0
	var _entity: WeakRef

	func entity() -> Node3D:
		return _entity.get_ref() as Node3D if _entity != null else null


## The characters that perceive `actor` or `victim` now (the victim always): what
## `AiFactions.witness_source` asks, so a reported act moves only the factions that saw it.
static func witnesses_of(actor: Node, victim: Node) -> Array:
	var found: Array = []
	if victim != null:
		found.append(victim)
	var tree := victim.get_tree() if victim != null and victim.is_inside_tree() else null
	if tree == null:
		return found
	for node in tree.get_nodes_in_group(GROUP):
		var senses := node as AiSenses
		if senses == null or senses._character == null or senses._character == victim:
			continue
		var of_actor := senses.beliefs.of(actor)
		var of_victim := senses.beliefs.of(victim)
		if (of_actor != null and of_actor.seen_now) or (of_victim != null and of_victim.seen_now):
			found.append(senses._character)
	return found


func _enter_tree() -> void:
	add_to_group(GROUP)


func _ready() -> void:
	_character = get_parent() as AiCharacter
	_query.collide_with_areas = false
	_query.collide_with_bodies = true
	if view != null:
		view.visible = show_view
	if _character == null:
		return
	_character.took_hit.connect(_on_took_hit)
	_character.died.connect(_on_died)
	var factions := AiFactions.find(self)
	if factions != null and not factions.witness_source.is_valid():
		factions.witness_source = AiSenses.witnesses_of


## One look, listen and settle, `seconds` after the last (the character's think calls it first).
func sense(seconds: float) -> void:
	if _character == null or (authority_only and not AiNoise.runs_here()):
		return
	var start := Time.get_ticks_usec()
	thinks += 1
	beliefs.clock += seconds
	var profile := _character.profile
	if profile == null or _character.is_dead():
		return
	_refresh_relations()
	_rays_left = profile.max_rays_per_think
	if sight and _character.tier != AiDirector.Tier.DORMANT:
		_look(profile, seconds)
	else:
		for belief: AiBelief in beliefs.by_id.values():
			belief.seen_now = false
	if hearing:
		_listen(profile)
	_settle(profile, seconds)
	if team:
		_send_shares(profile)
	_character.situation.feed_awareness(beliefs.top_awareness())
	last_rays = profile.max_rays_per_think - _rays_left
	last_sense_usec = Time.get_ticks_usec() - start


## Where it looks, in the world: the controller's look (or aim) when it has one, else ahead of
## the body.
func look_direction() -> Vector3:
	var controller := _character.ai_controller() if _character != null else null
	if controller != null and controller.look_direction.length_squared() > 0.000001:
		return controller.look_direction.normalized()
	return (
		Vector3.BACK.rotated(Vector3.UP, _character.facing) if _character != null else Vector3.BACK
	)


## Where it sees from.
func eye_position() -> Vector3:
	if eye != null:
		return eye.global_position
	return _character.global_position + Vector3.UP * 1.55


## Awareness a second for `body` seen at `distance`, `angle` radians off the look, in `band`:
## `1 / time_to_notice` scaled down far, to the side, still, crouched, lying down and Unfriendly.
func sight_rate(body: Node3D, distance: float, angle: float, band: int) -> float:
	var profile := _character.profile
	var rate := 1.0 / maxf(profile.time_to_notice, 0.001)
	rate *= lerpf(1.0, far_share, clampf(distance / maxf(profile.sight_range, 0.001), 0.0, 1.0))
	var half := deg_to_rad(maxf(profile.half_angle, 0.001))
	rate *= lerpf(1.0, side_share, clampf(angle / half, 0.0, 1.0))
	var character := body as Character
	if character != null:
		var moving := clampf(character.ground_speed() / maxf(profile.walk_speed, 0.01), 0.0, 1.0)
		rate *= lerpf(still_share, 1.0, moving)
		if character.prone:
			rate *= prone_share
		elif character.crouching:
			rate *= crouch_share
	if band != AiRelations.Band.HOSTILE:
		rate *= unfriendly_share
	return rate


## Takes a telling from an ally: the thing is believed (as told) after its own reaction delay,
## and passed on once. A telling it already had is dropped.
func receive(share: Share) -> void:
	if _character == null or _character.is_dead() or _share_keys.has(share.key):
		return
	_share_keys[share.key] = true
	shares_received += 1
	var node := share.entity()
	if node == null:
		return
	_refresh_relations()
	var belief := beliefs.track(node, share.member)
	belief.band = _band(share.member)
	if not belief.seen_now:
		belief.source = AiBelief.Source.TOLD
		belief.last_position = share.position
		belief.velocity = share.velocity
		belief.confidence = maxf(belief.confidence, 0.8)
	belief.time = beliefs.clock
	_raise(belief, 1.0)
	_queue_share(belief, share.key)


func _refresh_relations() -> void:
	if _member == null or not is_instance_valid(_member):
		_member = AiFactionMember.of(_character)
	_factions = _member.level() if _member != null else null
	if _factions != null and _factions.relations == null:
		_factions = null


# The band of the character toward `other` (Neutral without relations or a member).
func _band(other: AiFactionMember) -> int:
	if _factions == null or _member == null or other == null:
		return AiRelations.Band.NEUTRAL
	return _factions.band_of_members(_member, other)


func _look(profile: AiProfile, seconds: float) -> void:
	var me := _character.global_position
	var origin := eye_position()
	var look := look_direction()
	var cos_half := cos(deg_to_rad(profile.half_angle))
	var sight_reach := profile.sight_range * profile.sight_range
	var keep := maxf(profile.lose_sight_range, profile.sight_range)
	var keep_reach := keep * keep
	var near_reach := profile.near_radius * profile.near_radius
	_looked.clear()
	_visible.clear()
	_candidates.clear()
	_candidate_bands.clear()
	_candidate_near.clear()
	var tree := get_tree()
	for group in target_groups:
		for node: Node in _members_of(tree, group):
			var body := node as Node3D
			if body == null or body == _character or not is_instance_valid(body):
				continue
			var id := body.get_instance_id()
			if _looked.has(id):
				continue
			_looked[id] = true
			var far := me.distance_squared_to(body.global_position)
			var belief: AiBelief = beliefs.by_id.get(id, null)
			var reach := keep_reach if belief != null and belief.seen_now else sight_reach
			if far > reach and far > near_reach:
				continue
			var other := belief.member if belief != null else AiFactionMember.of(body)
			var band := _band(other)
			if band > care_up_to:
				continue
			var character := body as Character
			if character != null and character.is_dead():
				continue
			var near := far <= near_reach
			if not near and look.dot((_aim_point(body) - origin).normalized()) < cos_half:
				continue
			_candidates.append(body)
			_candidate_bands.append(band)
			_candidate_near.append(near)
	_cast_rays(origin)
	for index in _candidates.size():
		var body := _candidates[index]
		var id := body.get_instance_id()
		var fresh := _ray_at.has(id) and beliefs.clock - _ray_at[id] <= ray_fresh_seconds + 0.0001
		if fresh and _ray_clear[id]:
			_visible[id] = true
			_see(body, _candidate_bands[index], _candidate_near[index], origin, look, seconds)
	for id in beliefs.by_id:
		if not _visible.has(id):
			beliefs.by_id[id].seen_now = false
	if _ray_at.size() > 256:
		_ray_at.clear()
		_ray_clear.clear()


# Casts at most the rays left this think (and the budget allows), at the candidates whose last
# answer is oldest, the ones at arm's reach first.
func _cast_rays(origin: Vector3) -> void:
	var count := _candidates.size()
	var cast := 0
	while _rays_left > 0 and cast < count:
		var best := -1
		var oldest := INF
		for index in count:
			var id := _candidates[index].get_instance_id()
			var at: float = _ray_at.get(id, -INF)
			if at >= beliefs.clock:
				continue
			if _candidate_near[index]:
				at -= 1000000.0
			if best < 0 or at < oldest:
				best = index
				oldest = at
		if best < 0:
			return
		var body := _candidates[best]
		var line := _line(origin, _aim_point(body))
		if line == Line.REFUSED:
			return
		_ray_at[body.get_instance_id()] = beliefs.clock
		_ray_clear[body.get_instance_id()] = line == Line.CLEAR
		cast += 1


# One line test from `from` to `to` against `sight_mask`, from this think's rays and the
# director's budget.
func _line(from: Vector3, to: Vector3) -> Line:
	if _rays_left <= 0:
		return Line.REFUSED
	if _character.budget != null and not _character.budget.take_ray():
		return Line.REFUSED
	_rays_left -= 1
	rays_cast += 1
	_query.from = from
	_query.to = to
	_query.collision_mask = sight_mask
	var hit := _character.get_world_3d().direct_space_state.intersect_ray(_query)
	return Line.CLEAR if hit.is_empty() else Line.BLOCKED


func _aim_point(body: Node3D) -> Vector3:
	var character := body as Character
	var height := character.body_height() if character != null else 1.6
	return body.global_position + Vector3.UP * height * target_height_share


func _see(
	body: Node3D, band: int, near: bool, origin: Vector3, look: Vector3, seconds: float
) -> void:
	var belief := beliefs.track(body, AiFactionMember.of(body))
	var was_seen := belief.seen_now
	belief.band = band
	belief.seen_now = true
	belief.source = AiBelief.Source.SEEN
	var moving := body as CharacterBody3D
	belief.velocity = moving.velocity if moving != null else Vector3.ZERO
	belief.last_position = body.global_position
	belief.time = beliefs.clock
	belief.confidence = 1.0
	if belief.first_clear_at < 0.0:
		belief.first_clear_at = beliefs.clock
	if near:
		_raise(belief, 1.0)
	elif was_seen:
		# The clock starts at the first clear ray: a thing just come into view earns nothing yet.
		var toward := _aim_point(body) - origin
		var angle := look.angle_to(toward)
		var rate := sight_rate(body, toward.length(), angle, band)
		_raise(belief, belief.awareness + rate * seconds)


func _listen(profile: AiProfile) -> void:
	if _board == null or not is_instance_valid(_board) or not _board.is_inside_tree():
		_board = AiNoise.find(self)
		if _board == null:
			return
	var ears := profile.hearing_range / _board.reference_hearing
	var me := _character.global_position
	var first := maxi(_heard_serial + 1, _board.oldest())
	for serial in range(first, _board.newest + 1):
		var noise := _board.noise_at(serial)
		if noise == null:
			continue
		var source := noise.source()
		if source == _character:
			continue
		var radius := noise.radius * ears
		var far := me.distance_squared_to(noise.position)
		if far > radius * radius:
			continue
		var band := _band(noise.member) if noise.member != null else AiRelations.Band.HOSTILE
		if band > care_up_to:
			continue
		var clear := radius * _board.occlusion
		if far > clear * clear:
			if _line(eye_position(), noise.position + Vector3.UP * 0.3) != Line.CLEAR:
				continue
		_hear(noise, source, band, 1.0 - sqrt(far) / maxf(radius, 0.001), profile)
	_heard_serial = _board.newest


func _hear(
	noise: AiNoiseRecord, source: Node3D, band: int, strength: float, profile: AiProfile
) -> void:
	heard.emit(noise.kind, noise.position, source)
	var belief := beliefs.track(source, noise.member)
	belief.band = band
	if not belief.seen_now:
		belief.source = AiBelief.Source.HEARD
		belief.last_position = noise.position
		belief.velocity = Vector3.ZERO
		belief.confidence = maxf(belief.confidence, strength)
	belief.time = beliefs.clock
	_raise(belief, maxf(belief.awareness, profile.suspicious_at) + heard_gain * strength)


func _raise(belief: AiBelief, value: float) -> void:
	belief.awareness = clampf(value, 0.0, 1.0)
	var profile := _character.profile
	if not belief.said_suspicious and belief.awareness >= profile.suspicious_at:
		belief.said_suspicious = true
		suspicious.emit(belief.entity(), belief)
	if not belief.noticed and belief.awareness >= 1.0:
		_notice(belief, false)


func _notice(belief: AiBelief, at_once: bool) -> void:
	var profile := _character.profile
	belief.noticed = true
	belief.noticed_at = beliefs.clock
	var delay := maxf(profile.reaction_time, AiProfile.REACTION_FLOOR)
	belief.react_at = beliefs.clock if at_once else beliefs.clock + delay
	alerted.emit(belief.entity(), belief)
	if at_once:
		_believe(belief)


func _believe(belief: AiBelief) -> void:
	if belief.believed:
		return
	belief.believed = true
	entity_noticed.emit(belief.entity(), belief)
	if belief.source != AiBelief.Source.TOLD:
		_queue_share(belief, -1)


# The reaction delays that ended, awareness falling for what was not perceived this think, and
# memories past `memory_seconds` forgotten.
func _settle(profile: AiProfile, seconds: float) -> void:
	var memory := maxf(profile.memory_seconds, 0.01)
	var faded: Array[int] = []
	for id in beliefs.by_id:
		var belief: AiBelief = beliefs.by_id[id]
		if belief.noticed and not belief.believed and beliefs.clock >= belief.react_at - 0.0001:
			_believe(belief)
		if belief.time >= beliefs.clock - 0.0001:
			continue
		var age := beliefs.clock - belief.time
		belief.confidence = clampf(1.0 - age / memory, 0.0, 1.0)
		var fall := (
			memory if belief.noticed or belief.source != AiBelief.Source.SEEN else glimpse_seconds
		)
		belief.awareness = maxf(belief.awareness - seconds / fall, 0.0)
		if not belief.noticed and belief.awareness <= 0.0:
			faded.append(id)
	for id in faded:
		beliefs.forget(id)
	for belief in beliefs.expire(profile.memory_seconds):
		entity_lost.emit(belief.entity_id, belief)


func _queue_share(belief: AiBelief, key: int) -> void:
	if not team or belief.entity() == null:
		return
	if key < 0:
		_next_share += 1
		key = _next_share
	_share_keys[key] = true
	if _share_keys.size() > 512:
		_share_keys.clear()
		_share_keys[key] = true
	var share := Share.new()
	share.key = key
	share._entity = weakref(belief.entity())
	share.member = belief.member
	share.position = belief.last_position
	share.velocity = belief.velocity
	share.due = beliefs.clock + _character.profile.share_delay
	_outbox.append(share)


# Tells the allies within `share_radius` the tellings that are due.
func _send_shares(profile: AiProfile) -> void:
	if _outbox.is_empty():
		return
	var due: Array[Share] = []
	for share in _outbox:
		if share.due <= beliefs.clock + 0.0001:
			due.append(share)
	if due.is_empty():
		return
	var reach := profile.share_radius * profile.share_radius
	var me := _character.global_position
	for node in get_tree().get_nodes_in_group(GROUP):
		var other := node as AiSenses
		if other == null or other == self or other._character == null or not other.team:
			continue
		if me.distance_squared_to(other._character.global_position) > reach:
			continue
		if not _is_ally(other):
			continue
		for share in due:
			other.receive(share)
	for share in due:
		_outbox.erase(share)


func _is_ally(other: AiSenses) -> bool:
	if _factions == null or _member == null:
		return false
	var theirs := AiFactionMember.of(other._character)
	return (
		theirs != null and _factions.band_of_members(theirs, _member) >= AiRelations.Band.FRIENDLY
	)


func _on_took_hit(_amount: float, source: Node3D) -> void:
	if not touch or _character == null or source == null or source == _character:
		return
	if authority_only and not AiNoise.runs_here():
		return
	_refresh_relations()
	var member := AiFactionMember.of(source)
	var band := _band(member)
	if band > care_up_to:
		return
	var belief := beliefs.track(source, member)
	belief.band = band
	belief.source = AiBelief.Source.TOUCHED
	belief.last_position = source.global_position
	belief.velocity = Vector3.ZERO
	belief.time = beliefs.clock
	belief.confidence = 1.0
	belief.awareness = 1.0
	belief.said_suspicious = true
	if not belief.noticed:
		_notice(belief, true)
	else:
		_believe(belief)
	_character.situation.feed_awareness(1.0)


func _on_died() -> void:
	beliefs.clear()
	_outbox.clear()


## Reads the target groups from the tree again at the next look (they are read once a physics
## frame for every senses node): for a test or a tool that adds targets and senses in one frame.
static func refresh_targets() -> void:
	_group_frame = -1


# The members of `group`, read from the tree once a physics frame for every senses node.
static func _members_of(tree: SceneTree, group: StringName) -> Array:
	var frame := Engine.get_physics_frames()
	if frame != _group_frame:
		_group_cache.clear()
		_group_frame = frame
	var found: Variant = _group_cache.get(group)
	if found == null:
		found = tree.get_nodes_in_group(group)
		_group_cache[group] = found
	return found
