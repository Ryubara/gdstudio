class_name ClientCombat
extends RefCounted
## The client's half of shots, hits and deaths (gdstudio #906): it plays the server's events on
## this screen and decides nothing. Its `NetClient` hands it every TICK (`on_tick`) and asks it
## each physics step to play what is due (`play_due`).
##
## - SHOT: the shooter's puppet fires a cosmetic shot from its own muzzle along the server's
##   heading (`Weapon.fire_cosmetic`: the flash, the sound, a projectile that hits nothing), with
##   the weapon the event names in its hands.
## - HIT: the impact of the surface at the server's point (`Impacts`: the mark, the effect, the
##   sound), a cosmetic projectile on its way there ends there, the health the server left is put
##   on the player or target hit (`Health.set_wire_value`: a target at zero falls), and a player hit
##   flinches on the part this screen finds at the point. A camera near the point shakes
##   (`NearHitShake`, from the impact or, with no surface found, called here); never sent.
## - DIED: the body takes the event's velocity and dies into its own ragdoll from the pose it is
##   in. REVIVED: it gets up where the server says (`Character.revive_at`), the pose blending there.
## - REJECTED: counted and said (`shot_rejected`); the shooter's own cosmetic shot changed nothing.
##
## Events about the local player (its health, its death, its getting up, a refusal) play at once:
## its body is drawn in the present. Every other one waits until the puppets are drawn at the
## server time of its TICK (`RemotePlayers.drawn_time`), so a puppet's shot leaves where the puppet
## is drawn and its hit lands as the cosmetic projectile gets there.

## A puppet fired (`projectile` is null for a ray or a blow).
signal shot_played(slot: int, projectile: Projectile)
## A HIT was played on `collider` (null when this screen found nothing at the point).
signal hit_played(event: NetEvent, collider: Object)
## A player died or got up on this screen.
signal died_played(slot: int)
signal revived_played(slot: int)
## The server refused the local player's shot of command `seq` (`ServerCombat.Reason`).
signal shot_rejected(seq: int, reason: int)

## Metres from a HIT's point within which a cosmetic projectile heading there ends there.
const STOP_RADIUS := 0.75
## How hard a flinch pushes (newton seconds): the HIT carries no strength.
const FLINCH_STRENGTH := 40.0
## Metres either side of a hit point along the shot where a body's hit zones are looked for.
const ZONE_REACH := 0.6

var client: NetClient
## Events played since the start, by kind.
var shots := 0
var hits := 0
var deaths := 0
var revives := 0
var rejected := 0
## Microseconds spent playing events, in all and the most one event took, by kind name.
var spent_us := {}
var worst_us := {}

var _pending: Array[NetEvent] = []
var _due: PackedFloat64Array = []
var _cosmetic: Array[Projectile] = []


func _init(owner: NetClient = null) -> void:
	client = owner


## The events of a TICK: the local player's play now, the others wait for the puppets.
func on_tick(tick: SnapshotCodec.Tick) -> void:
	var at := float(tick.server_tick) / NetLimits.TICK_RATE
	for event in tick.events:
		match event.kind:
			NetEvent.Kind.SHOT, NetEvent.Kind.HIT, NetEvent.Kind.DIED, NetEvent.Kind.REVIVED:
				if _is_local(event) or client.remote_players == null:
					play(event)
				else:
					_pending.append(event)
					_due.append(at)
			NetEvent.Kind.REJECTED:
				play(event)


## Plays every waiting event whose TICK is not later than `drawn` (server seconds; a negative time
## plays all).
func play_due(drawn: float) -> void:
	var count := 0
	while count < _pending.size() and (drawn < 0.0 or _due[count] <= drawn):
		count += 1
	if count == 0:
		return
	var due_now := _pending.slice(0, count)
	_pending = _pending.slice(count)
	_due = _due.slice(count)
	for event in due_now:
		play(event)


## Events waiting for the puppets.
func pending() -> int:
	return _pending.size()


## Forgets what waits (the client left).
func clear() -> void:
	_pending.clear()
	_due.clear()
	_cosmetic.clear()


## Plays one event now.
func play(event: NetEvent) -> void:
	var began := Time.get_ticks_usec()
	_play(event)
	var took := Time.get_ticks_usec() - began
	var kind: String = str(NetEvent.Kind.find_key(event.kind)).to_lower()
	spent_us[kind] = int(spent_us.get(kind, 0)) + took
	worst_us[kind] = maxi(int(worst_us.get(kind, 0)), took)


func _play(event: NetEvent) -> void:
	match event.kind:
		NetEvent.Kind.SHOT:
			_play_shot(event)
		NetEvent.Kind.HIT:
			_play_hit(event)
		NetEvent.Kind.DIED:
			_play_died(event)
		NetEvent.Kind.REVIVED:
			_play_revived(event)
		NetEvent.Kind.REJECTED:
			rejected += 1
			shot_rejected.emit(event.seq, event.code)


## The body of `slot` on this screen: the local player or its puppet, or null.
func body_of(slot: int) -> Player:
	if slot < 0 or client == null:
		return null
	if slot == client.slot:
		return client.player
	return client.remote_players.puppet_at(slot) if client.remote_players != null else null


## Keeps `projectile` (a cosmetic shot of this screen) to end it where the server's hit lands.
func track(projectile: Projectile) -> void:
	if projectile == null:
		return
	_cosmetic = _cosmetic.filter(
		func(shot: Projectile) -> bool: return is_instance_valid(shot) and shot.is_flying()
	)
	if not _cosmetic.has(projectile):
		_cosmetic.append(projectile)


func _is_local(event: NetEvent) -> bool:
	if client == null or client.slot < 0:
		return false
	match event.kind:
		NetEvent.Kind.HIT:
			return NetHits.slot_of(event.id) == client.slot
		NetEvent.Kind.DIED, NetEvent.Kind.REVIVED:
			return event.slot == client.slot
	return false


func _play_shot(event: NetEvent) -> void:
	var puppet := body_of(event.slot)
	if puppet == null or puppet == client.player or puppet.weapon == null:
		return
	if puppet.loadout != null:
		puppet.loadout.equip_now(event.amount - 1)
	var projectile := puppet.weapon.fire_cosmetic(event.point, event.direction)
	track(projectile)
	shots += 1
	shot_played.emit(event.slot, projectile)


func _play_hit(event: NetEvent) -> void:
	hits += 1
	var collider: Object = null
	match event.code:
		NetHits.Kind.PLAYER:
			var body := body_of(NetHits.slot_of(event.id))
			if body != null:
				collider = body
				_hurt(body, event)
		NetHits.Kind.TARGET:
			var target := NetHits.target_by_id(event.id, client)
			if target != null:
				collider = target
				_set_health(target, event.amount, true)
	if collider == null:
		var space := _space()
		var found := NetHits.probe(space, event.point, event.direction)
		collider = found.get("collider")
	_stop_cosmetic_at(event.point)
	var impacts := Impacts.find(client)
	if impacts != null and collider != null:
		# The impact's `impact_made` also shakes a camera near the point (`NearHitShake`).
		impacts.impact(collider, event.point, event.direction)
	else:
		NearHitShake.play_near(client, event.point)
	hit_played.emit(event, collider)


# The health the server left, and the flinch (or, lying, the push) this screen makes itself.
func _hurt(body: Character, event: NetEvent) -> void:
	# Zero is the DIED event's, which carries the velocity: a body is never killed by a HIT.
	_set_health(body, event.amount, false)
	body.hit_received.emit(_record_on(body, event))


func _set_health(thing: Node, amount: int, zero_kills: bool) -> void:
	var health := Health.of(thing)
	if health == null or amount == NetEvent.NO_HEALTH:
		return
	if amount <= 0 and not zero_kills:
		return
	health.set_wire_value(amount)


# A record of the hit on `body` for its own `HitReaction`: the part this screen's pose has at the
# point (no damage: the server took it).
func _record_on(body: Character, event: NetEvent) -> HitRecord:
	var along := -event.direction.normalized()
	var zones := HitZones.of(body)
	if zones != null and not body.is_dead():
		var found := zones.find(event.point - along * ZONE_REACH, event.point + along * ZONE_REACH)
		if not found.is_empty():
			var part: HitZone = found.zone
			return part.record(0.0, event.point, along, FLINCH_STRENGTH, null)
	var bone := &""
	if body.ragdoll_body != null and body.ragdoll_body.is_limp():
		bone = _nearest_bone(body.ragdoll_body, event.point)
	return HitRecord.shot(0.0, &"", bone, event.point, along, FLINCH_STRENGTH)


static func _nearest_bone(ragdoll: CharacterRagdoll, point: Vector3) -> StringName:
	var best := &""
	var best_distance := INF
	for entry: Dictionary in CharacterRagdoll.BODIES:
		var bone := ragdoll.body(entry.bone)
		if bone == null:
			continue
		var distance := bone.global_position.distance_squared_to(point)
		if distance < best_distance:
			best_distance = distance
			best = entry.bone
	return best


func _play_died(event: NetEvent) -> void:
	var body := body_of(event.slot)
	if body == null:
		return
	deaths += 1
	if not body.is_dead():
		body.velocity = event.point
		body.die()
	died_played.emit(event.slot)


func _play_revived(event: NetEvent) -> void:
	var body := body_of(event.slot)
	if body == null:
		return
	revives += 1
	body.revive_at(event.point)
	if body == client.player:
		client.reconciler.reset()
		client.reconciler.snap_next = true
	revived_played.emit(event.slot)


func _stop_cosmetic_at(point: Vector3) -> void:
	for shot in _cosmetic:
		if not is_instance_valid(shot) or not shot.is_flying():
			continue
		var heading := shot.velocity.normalized()
		var to_point := point - shot.global_position
		var ahead := to_point.dot(heading)
		var off_line := (to_point - heading * ahead).length()
		if off_line <= STOP_RADIUS:
			shot.stop_at(point)


func _space() -> PhysicsDirectSpaceState3D:
	var spatial := client.player as Node3D if client != null else null
	if spatial == null or not spatial.is_inside_tree():
		return null
	return spatial.get_world_3d().direct_space_state
