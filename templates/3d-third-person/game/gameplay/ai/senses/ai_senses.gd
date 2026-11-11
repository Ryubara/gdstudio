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
##   an ally that did not know it believes it (after its own reaction delay) and passes the telling
##   on once; one that knew already passes nothing on.
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
## The height of a target that is not a `Character` (and the cone's aim at any target).
const STANDING_HEIGHT := 1.6

static var _next_share := 0
static var _everyone: Array[AiSenses] = []

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
# The serials one listen reads (kept between thinks, so a listen makes no array).
var _heard_serials: Array[int] = []
var _ray_at: Dictionary[int, float] = {}
var _ray_clear: Dictionary[int, bool] = {}
var _visible: Dictionary[int, bool] = {}
var _candidates: Array[Node3D] = []
var _candidate_points := PackedVector3Array()
# Each candidate's band times 2, plus 1 when it is at arm's reach.
var _candidate_flags := PackedInt32Array()
# The senses' clock of each candidate's last ray (-INF: never).
var _candidate_ages := PackedFloat64Array()
var _outbox: Array[Share] = []
# The awareness rate's numbers, made once and read again at each think that sees something.
var _rates := Rates.new()
var _share_keys: Dictionary[int, bool] = {}


## The numbers of the awareness rate, read once a think from the profile and the senses.
class Rates:
	var base := 1.0
	var per_metre := 0.0
	var per_radian := 0.0
	var per_speed := 0.0
	var far_share := 0.3
	var side_share := 0.5
	var still_share := 0.7
	var crouch_share := 0.6
	var prone_share := 0.35
	var unfriendly_share := 0.5

	func read(profile: AiProfile, senses: AiSenses) -> void:
		base = 1.0 / maxf(profile.time_to_notice, 0.001)
		per_metre = 1.0 / maxf(profile.sight_range, 0.001)
		per_radian = 1.0 / deg_to_rad(maxf(profile.half_angle, 0.001))
		per_speed = 1.0 / maxf(profile.walk_speed, 0.01)
		far_share = senses.far_share
		side_share = senses.side_share
		still_share = senses.still_share
		crouch_share = senses.crouch_share
		prone_share = senses.prone_share
		unfriendly_share = senses.unfriendly_share

	func rate(body: Node3D, distance: float, angle: float, band: int) -> float:
		var value := base * lerpf(1.0, far_share, clampf(distance * per_metre, 0.0, 1.0))
		value *= lerpf(1.0, side_share, clampf(angle * per_radian, 0.0, 1.0))
		var character := body as Character
		if character != null:
			var moving := clampf(character.ground_speed() * per_speed, 0.0, 1.0)
			value *= lerpf(still_share, 1.0, moving)
			if character.prone:
				value *= prone_share
			elif character.crouching:
				value *= crouch_share
		if band != AiRelations.Band.HOSTILE:
			value *= unfriendly_share
		return value


## A telling on its way to the allies.
class Share:
	var key := 0
	var entity_id := 0
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
	for senses in _everyone:
		if senses._character == null or senses._character == victim:
			continue
		if not senses.is_inside_tree() or senses.get_tree() != tree:
			continue
		var of_actor := senses.beliefs.of(actor)
		var of_victim := senses.beliefs.of(victim)
		if (of_actor != null and of_actor.seen_now) or (of_victim != null and of_victim.seen_now):
			found.append(senses._character)
	return found


func _enter_tree() -> void:
	add_to_group(GROUP)
	_everyone.append(self)


func _exit_tree() -> void:
	_everyone.erase(self)


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
		_visible.clear()
		_clear_seen()
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
	var rates := Rates.new()
	rates.read(_character.profile, self)
	return rates.rate(body, distance, angle, band)


## Takes a telling from an ally: the thing is believed (as told) after its own reaction delay,
## and passed on once. A telling it already had is dropped.
func receive(share: Share) -> void:
	if _character == null or _character.is_dead() or _share_keys.has(share.key):
		return
	_share_keys[share.key] = true
	shares_received += 1
	var known: AiBelief = beliefs.by_id.get(share.entity_id, null)
	if known != null and known.believed:
		# It knows already: nothing to learn and nothing to pass on (a crowd that all sees one
		# thing tells nobody anything twice).
		return
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


## The first body of the target groups the character may not hurt (`AiFactions.can_hurt` false:
## a friend whose faction does not hurt friends) standing within `radius` of the line from its eyes
## to `point`, or null: the brain does not fire through it. A geometric test over the shared pools,
## no ray.
func friend_in_line_of_fire(point: Vector3, radius := 0.6) -> Node3D:
	if _character == null:
		return null
	_refresh_relations()
	if _factions == null or _member == null:
		return null
	var from := eye_position()
	var line := point - from
	var length_squared := line.length_squared()
	if length_squared < 0.0001:
		return null
	var table := _factions.relations
	var mine := (
		_member.refresh(table) if _member.table_version != table.version else _member.faction_index
	)
	var reach := radius * radius
	# A chest in the way stands within `radius` (flat) of the segment, so inside its flat box grown
	# by `radius`: four comparisons skip a friend anywhere else (behind, beyond, far to the side).
	var margin := radius + 0.01
	var low_x := minf(from.x, point.x) - margin
	var high_x := maxf(from.x, point.x) + margin
	var low_z := minf(from.z, point.z) - margin
	var high_z := maxf(from.z, point.z) + margin
	for group in target_groups:
		var pool := AiSensePool.of(get_tree(), group, table)
		for part in pool.factions.size():
			if table.band_at(mine, pool.factions[part]) < AiRelations.Band.FRIENDLY:
				continue
			for node: Variant in pool.nodes[part]:
				if not is_instance_valid(node) or node == _character:
					continue
				var body := node as Node3D
				var at := body.global_position
				if at.x < low_x or at.x > high_x or at.z < low_z or at.z > high_z:
					continue
				var chest := at + Vector3.UP * 1.0
				var along := (chest - from).dot(line) / length_squared
				if along <= 0.0 or along >= 1.0:
					continue
				var nearest := from + line * along
				var off := Vector2(nearest.x - chest.x, nearest.z - chest.z).length_squared()
				if off > reach or absf(nearest.y - chest.y) > 1.0:
					continue
				if not AiFactions.can_hurt(_character, body):
					return body
	return null


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
	_visible.clear()
	_candidates.clear()
	_candidate_points.clear()
	_candidate_flags.clear()
	_candidate_ages.clear()
	if _factions == null or _member == null:
		_clear_seen()
		return
	var me := _character.global_position
	var origin := eye_position()
	var look := look_direction()
	var cos_half := cos(deg_to_rad(profile.half_angle))
	var sight_reach := profile.sight_range * profile.sight_range
	var keep := maxf(profile.lose_sight_range, profile.sight_range)
	var keep_reach := keep * keep
	var near_reach := profile.near_radius * profile.near_radius
	var lift := Vector3.UP * (STANDING_HEIGHT * target_height_share)
	var table := _factions.relations
	var mine := (
		_member.refresh(table) if _member.table_version != table.version else _member.faction_index
	)
	var grudges := _member.holds_grudges
	var tree := get_tree()
	for group in target_groups:
		var pool := AiSensePool.of(tree, group, table)
		for part in pool.factions.size():
			var band := table.band_at(mine, pool.factions[part])
			if band > care_up_to and not grudges:
				continue
			var nodes: Array = pool.nodes[part]
			for index in nodes.size():
				var node: Variant = nodes[index]
				if not is_instance_valid(node) or node == _character:
					continue
				var body := node as Node3D
				var at := body.global_position
				var far := me.distance_squared_to(at)
				if far > sight_reach and far > near_reach:
					if far > keep_reach or not _was_seen(body):
						continue
				var near := far <= near_reach
				if not near and look.dot((at + lift - origin).normalized()) < cos_half:
					continue
				var felt := band
				if grudges:
					felt = _band(pool.members[part][index])
					if felt > care_up_to:
						continue
				var character := body as Character
				if character != null and character.is_dead():
					continue
				_candidates.append(body)
				_candidate_points.append(
					at + Vector3.UP * (_height_of(character) * target_height_share)
				)
				_candidate_flags.append(felt * 2 + (1 if near else 0))
				_candidate_ages.append(_ray_at.get(body.get_instance_id(), -INF))
	if not _candidates.is_empty():
		_cast_rays(origin)
		var fresh_after := beliefs.clock - ray_fresh_seconds - 0.0001
		var rates_read := false
		for index in _candidates.size():
			if _candidate_ages[index] < fresh_after:
				continue
			var body := _candidates[index]
			var id := body.get_instance_id()
			if not _ray_clear[id] or _visible.has(id):
				continue
			_visible[id] = true
			if not rates_read:
				_rates.read(profile, self)
				rates_read = true
			_see(index, _candidate_points[index] - origin, look, seconds, _rates)
	_clear_seen()
	if _ray_at.size() > 256:
		_ray_at.clear()
		_ray_clear.clear()


func _was_seen(body: Node3D) -> bool:
	var belief: AiBelief = beliefs.by_id.get(body.get_instance_id(), null)
	return belief != null and belief.seen_now


# Every belief not in sight this think is no longer seen now.
func _clear_seen() -> void:
	for id in beliefs.by_id:
		if not _visible.has(id):
			beliefs.by_id[id].seen_now = false


# Casts at most the rays left this think (and the budget allows), at the candidates whose last
# answer is oldest, the ones at arm's reach first; a candidate's age becomes the think's clock.
func _cast_rays(origin: Vector3) -> void:
	var count := _candidates.size()
	while _rays_left > 0:
		var best := -1
		var oldest := INF
		for index in count:
			var at := _candidate_ages[index]
			if at >= beliefs.clock:
				continue
			if _candidate_flags[index] & 1:
				at -= 1000000.0
			if at < oldest:
				best = index
				oldest = at
		if best < 0:
			return
		var line := _line(origin, _candidate_points[best])
		if line == Line.REFUSED:
			return
		var id := _candidates[best].get_instance_id()
		_ray_at[id] = beliefs.clock
		_ray_clear[id] = line == Line.CLEAR
		_candidate_ages[best] = beliefs.clock


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


static func _height_of(character: Character) -> float:
	return character.body_height() if character != null else STANDING_HEIGHT


func _see(index: int, toward: Vector3, look: Vector3, seconds: float, rates: Rates) -> void:
	var body := _candidates[index]
	var band := _candidate_flags[index] >> 1
	var belief: AiBelief = beliefs.by_id.get(body.get_instance_id(), null)
	if belief == null:
		belief = beliefs.track(body, AiFactionMember.of(body))
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
	if belief.noticed:
		return
	if _candidate_flags[index] & 1:
		_raise(belief, 1.0)
	elif was_seen:
		# The clock starts at the first clear ray: a thing just come into view earns nothing yet.
		var rate := rates.rate(body, toward.length(), look.angle_to(toward), band)
		_raise(belief, belief.awareness + rate * seconds)


func _listen(profile: AiProfile) -> void:
	if _board == null or not is_instance_valid(_board) or not _board.is_inside_tree():
		_board = AiNoise.find(self)
		if _board == null:
			return
	var ears := profile.hearing_range / _board.reference_hearing
	var me := _character.global_position
	var table := _factions.relations if _factions != null else null
	var mine := -1
	if table != null and _member != null:
		mine = (
			_member.refresh(table)
			if _member.table_version != table.version
			else _member.faction_index
		)
	var first := maxi(_heard_serial + 1, _board.oldest())
	if first > _board.newest:
		_heard_serial = _board.newest
		return
	var kept_from := _board.first_kept_frame()
	if table == null or _member == null or _member.holds_grudges:
		# A grudge is held toward one maker, not a faction: every noise is read.
		for serial in range(first, _board.newest + 1):
			_listen_to(serial, kept_from, me, ears, table, mine, profile)
	else:
		# Only the factions it cares about (one band read for each), oldest first as made.
		_heard_serials.clear()
		var parts := 0
		for faction: StringName in _board.by_faction:
			if table.band_at(mine, table.index_of(faction)) > care_up_to:
				continue
			if _board.serials_since(_board.by_faction[faction], first, _heard_serials):
				parts += 1
		if _board.serials_since(_board.unowned, first, _heard_serials):
			parts += 1
		if parts > 1:
			_heard_serials.sort()
		for serial in _heard_serials:
			_listen_to(serial, kept_from, me, ears, table, mine, profile)
	_heard_serial = _board.newest


# Hears the noise with `serial` when it is still kept, within its radius and not muffled, and its
# maker one the character cares about.
func _listen_to(
	serial: int,
	kept_from: int,
	me: Vector3,
	ears: float,
	table: AiRelations,
	mine: int,
	profile: AiProfile
) -> void:
	var noise := _board.record(serial)
	if noise == null or noise.frame < kept_from:
		return
	var radius := noise.radius * ears
	var far := me.distance_squared_to(noise.position)
	if far > radius * radius:
		return
	var source := noise.source()
	if source == _character:
		return
	# Its maker was freed since (a despawn): the record's member is gone with it.
	if noise.maker_gone():
		return
	var band := _noise_band(noise.member, table, mine)
	if band > care_up_to:
		return
	var clear := radius * _board.occlusion
	if far > clear * clear:
		if _line(eye_position(), noise.position + Vector3.UP * 0.3) != Line.CLEAR:
			return
	_hear(noise, source, band, 1.0 - sqrt(far) / maxf(radius, 0.001), profile)


# The band toward what made a noise: Hostile for something unknown, the factions' (one byte read)
# unless the character holds grudges.
func _noise_band(other: AiFactionMember, table: AiRelations, mine: int) -> int:
	if other == null:
		return AiRelations.Band.HOSTILE
	if table == null:
		return AiRelations.Band.NEUTRAL
	if _member.holds_grudges:
		return _band(other)
	var side := (
		other.refresh(table) if other.table_version != table.version else other.faction_index
	)
	return table.band_at(mine, side)


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
	share.entity_id = belief.entity_id
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
	for other in _everyone:
		if other == self or other._character == null or not other.team:
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
