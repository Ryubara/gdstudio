class_name AiHitHistory
extends RefCounted
## The volume a shot meets of each AI character, for the last `ticks` server ticks (gdstudio
## #1198): where its feet were and how wide and tall its capsule was, recorded with the TICK's rows
## (every `every` ticks, from the same positions), so the place of tick T here is the place a
## client was sent for T; a tick between two records is the straight line between them, as a
## client's glide walks it. `ShotRewind` reads it to meet a player's shot with the AI where the
## shooter's screen drew it. Only the volume is kept: the AI's brain, senses and navigation are
## never rewound. `NetServer` owns one (`ai_history`) and records it at each TICK.

## Ticks kept (36: 0.6 s at 60 a second, a client 200 ms away each way and its playout buffer).
var ticks := 36
## Ticks between two records (`NetServer.SEND_EVERY`); the ticks recorded are its multiples.
var every := 1
## Microseconds the last `record` took.
var last_record_us := 0

var _tracks: Dictionary[int, Track] = {}
var _newest := -1


## One character's records, a ring of `AiHitHistory._slots()` (written in place).
class Track:
	extends RefCounted
	var body: AiCharacter
	var capsule: CapsuleShape3D
	var since := 0
	var places := PackedVector3Array()
	## The capsule's radius and height (a height of 0: dead).
	var sizes := PackedVector2Array()


func _init(kept_ticks := 36, record_every := 1) -> void:
	every = maxi(record_every, 1)
	ticks = maxi(kept_ticks, every)


## Records every character of `characters` (wire id to character) at server tick `tick` (a
## multiple of `every`); a character no longer there is forgotten.
func record(tick: int, characters: Dictionary[int, AiCharacter]) -> void:
	var began := Time.get_ticks_usec()
	for id: int in _tracks.keys():
		if not characters.has(id) or not is_instance_valid(_tracks[id].body):
			_tracks.erase(id)
	var at := _slot(tick)
	for id: int in characters:
		var body := characters[id]
		if not is_instance_valid(body) or not body.is_inside_tree():
			continue
		var track: Track = _tracks.get(id)
		if track == null or track.body != body:
			track = _start(id, body, tick)
		track.places[at] = body.global_position
		if body.is_dead() or track.capsule == null:
			track.sizes[at] = Vector2.ZERO
		else:
			track.sizes[at] = Vector2(track.capsule.radius, track.capsule.height)
	_newest = tick
	last_record_us = Time.get_ticks_usec() - began


## Forgets character `id`.
func forget(id: int) -> void:
	_tracks.erase(id)


## The newest tick recorded (-1 before the first).
func newest() -> int:
	return _newest


## The oldest tick still kept.
func oldest() -> int:
	return maxi(_newest - ticks + 1, 0)


## The ids recorded.
func ids() -> Array[int]:
	return _tracks.keys()


## The character of id `id`, or null.
func body_of(id: int) -> AiCharacter:
	var track: Track = _tracks.get(id)
	return track.body if track != null and is_instance_valid(track.body) else null


## Whether character `id` was recorded at `tick`.
func has(id: int, tick: int) -> bool:
	var track: Track = _tracks.get(id)
	if track == null:
		return false
	return tick >= maxi(oldest(), track.since) and tick <= _newest


## Where character `id`'s feet were at `tick`, held to the ticks kept for it (`Vector3.INF` for
## one not recorded); between two records, the line between them.
func position_at(id: int, tick: int) -> Vector3:
	var track: Track = _tracks.get(id)
	if track == null or _newest < 0:
		return Vector3.INF
	var held := clampi(tick, maxi(oldest(), track.since), _newest)
	var first := held - posmod(held, every)
	if first == held or first + every > _newest:
		return track.places[_slot(first)]
	var share := float(held - first) / every
	return track.places[_slot(first)].lerp(track.places[_slot(first + every)], share)


## Its capsule's radius and height at `tick`, held as `position_at` is, from the record at or
## before it (a height of 0: dead).
func size_at(id: int, tick: int) -> Vector2:
	var track: Track = _tracks.get(id)
	if track == null or _newest < 0:
		return Vector2.ZERO
	var held := clampi(tick, maxi(oldest(), track.since), _newest)
	return track.sizes[_slot(held - posmod(held, every))]


# The records kept of a character.
func _slots() -> int:
	return ceili(float(ticks) / every) + 1


func _slot(tick: int) -> int:
	return posmod(floori(float(tick) / every), _slots())


func _start(id: int, body: AiCharacter, tick: int) -> Track:
	var track := Track.new()
	track.body = body
	track.since = tick
	track.places.resize(_slots())
	track.sizes.resize(_slots())
	# The body's own capsule, which it sizes for the crouch, the slide and the prone stance.
	var shape := body.get_node_or_null(^"%Body") as CollisionShape3D
	track.capsule = shape.shape as CapsuleShape3D if shape != null else null
	_tracks[id] = track
	return track
