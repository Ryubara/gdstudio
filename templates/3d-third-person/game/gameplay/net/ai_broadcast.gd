class_name AiBroadcast
extends RefCounted
## The server's half of the AI on the wire (gdstudio #970): it gives each AI character of the map a
## wire id (the meta `NetHits.AI_META`), turns the characters into rows once a TICK (`build`), and
## makes each client's block from them (`block_for`, `AiSnapshot.encode`); what happens to a
## character once (it is alerted, fires, dies, gets up) becomes a small AI event for each client
## that holds it (`tell_holders`). `NetServer` owns one.
##
## Only the characters the map's `AiDirector` manages are sent: one the population cap refused or
## parked stands frozen on the server and is in no snapshot. The server's AI weapons fire real
## shots with no flash, sound or mark (`Weapon.effects` off), and what they meet is a HIT
## (`hit_made`, `ServerCombat.send_hit`). Nothing cosmetic is sent: a client plays the bark, the
## muzzle flash, the ragdoll and the footsteps itself.

## The section's origin: positions on the wire are centimetres from it.
var origin := Vector3.ZERO
var rates: AiTierRates
## A character's look on the wire is the index of its profile here (0 for one not listed).
var variants: Array[AiProfile] = []
## `func(id: int, event: NetEvent)`: to each client that holds character `id`.
var tell_holders := Callable()
## `func(collider: Object, point: Vector3, normal: Vector3)`: what an AI's shot met.
var hit_made := Callable()
## Rows that could not travel (a number that was not finite).
var drops := NetDrops.new()
## Microseconds the last `build` took, and the `block_for` calls since `take_encode_us`.
var last_build_us := 0
var encode_us := 0
## Events sent since the start, by `NetEvent.AiCode`.
var events := {}

var _root: Node
var _characters: Dictionary[int, AiCharacter] = {}
var _rows: Array[AiRow] = []
var _next_id := 0


func _init(map_root: Node = null, tier_rates: AiTierRates = null) -> void:
	_root = map_root
	rates = tier_rates if tier_rates != null else AiTierRates.new()


## The characters with a wire id, by id.
func characters() -> Dictionary[int, AiCharacter]:
	return _characters


## The rows of the last `build`.
func rows() -> Array[AiRow]:
	return _rows


## The character of wire id `id`, or null.
func character_of(id: int) -> AiCharacter:
	var found: AiCharacter = _characters.get(id)
	return found if is_instance_valid(found) else null


## Finds the map's AI characters (a new one gets a wire id and is watched; a freed one is
## forgotten) and makes this TICK's rows of those that are sent.
func build() -> void:
	var began := Time.get_ticks_usec()
	_find()
	_rows.clear()
	var ids: Array[int] = _characters.keys()
	ids.sort()
	for id in ids:
		var character := _characters[id]
		if not _is_sent(character):
			continue
		_rows.append(row_of(id, character))
	last_build_us = Time.get_ticks_usec() - began


## The block of one client for server tick `tick` (`AiSnapshot.encode` with this broadcast's rows).
func block_for(view: AiPeerView, tick: int, full := false) -> PackedByteArray:
	var began := Time.get_ticks_usec()
	var block := AiSnapshot.encode(_rows, view, rates, tick, drops, full)
	encode_us += Time.get_ticks_usec() - began
	return block


## The microseconds the blocks took since the last call, and starts counting again.
func take_encode_us() -> int:
	var spent := encode_us
	encode_us = 0
	return spent


## The row of `character`, wire id `id`.
func row_of(id: int, character: AiCharacter) -> AiRow:
	var row := AiRow.new()
	row.id = id
	row.position = character.global_position - origin
	row.yaw = character.facing
	row.speed = Vector2(character.velocity.x, character.velocity.z).length()
	row.situation = character.situation.current
	row.state = character.state
	row.aiming = character.aiming
	row.target = _target_of(character)
	row.variant = maxi(variants.find(character.profile), 0)
	return row


func _is_sent(character: AiCharacter) -> bool:
	if not is_instance_valid(character) or not character.is_inside_tree():
		return false
	# Managed by a director, or stepping itself where there is none; refused or parked: frozen.
	return character.director != null or character.is_physics_processing()


func _find() -> void:
	for id: int in _characters.keys():
		if not is_instance_valid(_characters[id]):
			_characters.erase(id)
	if _root == null or not _root.is_inside_tree():
		return
	for node in _root.get_tree().get_nodes_in_group(AiCharacter.GROUP):
		var character := node as AiCharacter
		if character == null or character.has_meta(NetHits.AI_META):
			continue
		if character != _root and not _root.is_ancestor_of(character):
			continue
		watch(character)


## Gives `character` a wire id and turns what happens to it into events.
func watch(character: AiCharacter) -> int:
	var id := _take_id()
	if id < 0:
		return -1
	character.set_meta(NetHits.AI_META, id)
	_characters[id] = character
	character.died.connect(_on_died.bind(id, character))
	character.revived.connect(_tell.bind(id, NetEvent.AiCode.REVIVED))
	character.situation_changed.connect(_on_situation.bind(id))
	var weapon := character.weapon
	if weapon != null:
		weapon.effects = false
		weapon.authoritative = true
		weapon.fired.connect(_on_fired.bind(id, character))
		weapon.hit_scanned.connect(_on_scanned)
	return id


func _take_id() -> int:
	for _try in NetLimits.MAX_AI_ID + 1:
		var id := _next_id
		_next_id = (_next_id + 1) % (NetLimits.MAX_AI_ID + 1)
		if not _characters.has(id):
			return id
	return -1


func _target_of(character: AiCharacter) -> int:
	var brain := character.brain as AiBrain
	if brain == null or not is_instance_valid(brain.target):
		return AiSnapshot.NO_TARGET
	var id := NetHits.id_of(brain.target)
	return id if id != NetEvent.NO_ID else AiSnapshot.NO_TARGET


func _on_died(id: int, character: AiCharacter) -> void:
	_tell(id, NetEvent.AiCode.DIED, character.velocity)


# Alerted: the situation rose to Alert or Engaged from calmer.
func _on_situation(now: int, previous: int, id: int) -> void:
	var alert := AiSituation.Situation.ALERT
	if AiSituation.RANK[now] >= AiSituation.RANK[alert] and now != AiSituation.Situation.DEAD:
		if AiSituation.RANK[previous] < AiSituation.RANK[alert]:
			_tell(id, NetEvent.AiCode.ALERTED)


func _on_fired(projectile: Projectile, id: int, character: AiCharacter) -> void:
	var weapon := character.weapon
	_tell(id, NetEvent.AiCode.FIRED, weapon.last_origin, weapon.last_heading)
	if projectile != null and not projectile.impacted.is_connected(_on_impacted):
		projectile.impacted.connect(_on_impacted)


func _on_impacted(collider: Node, point: Vector3, normal: Vector3) -> void:
	if hit_made.is_valid():
		hit_made.call(collider, point, normal)


func _on_scanned(hit: Dictionary) -> void:
	if hit_made.is_valid():
		hit_made.call(
			hit.get("collider"), hit.get("position", Vector3.ZERO), hit.get("normal", Vector3.UP)
		)


func _tell(id: int, code: NetEvent.AiCode, at := Vector3.ZERO, way := Vector3.FORWARD) -> void:
	events[code] = int(events.get(code, 0)) + 1
	if tell_holders.is_valid():
		tell_holders.call(id, NetEvent.ai(id, code, at, way))
