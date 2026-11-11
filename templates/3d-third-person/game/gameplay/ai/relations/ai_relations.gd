@tool
class_name AiRelations
extends Resource
## Who is hostile, neutral or friendly to whom, and how that changes: the factions (each with its
## row of base attitudes), the bands the numbers fall in, the events that move them and how fast
## they drift back. One file per game (`ai_relations.tres`); a game with three player teams edits
## the file, nothing in code names a faction.
##
## Every ordered pair (A toward B) has a base and a current attitude, -100 to 100; A toward B is
## not B toward A. The band of a pair moves with **hysteresis**: it enters a band farther from
## Neutral at the band's line (Hostile at `hostile_at`), and leaves back toward Neutral only
## `hysteresis` past the line (Hostile at -40 by default), so a value that wobbles on a line
## changes the band once. The current value drifts back to the base at `recovery_per_minute`
## (`recover()`, which the level's `AiFactions` calls).
##
## Lookups by faction index (`band_at`, `attitude_at`) are reads of packed arrays and allocate
## nothing; the lookups by name add one dictionary read. A faction not in the table is at
## `default_attitude` toward everyone and everyone toward it.
##
## The runtime state (current values and bands) lives in this resource; the `AiFactions` node
## plays a copy, so a level never writes the file loaded from disk.

## The band of a pair changed (`Band`), `a` toward `b` by faction id.
signal band_changed(a: StringName, b: StringName, previous: int, now: int)
## A pair was set or moved by an event (not by recovery): what a server sends (`encode_change`).
signal attitude_changed(a: int, b: int)

## The named bands, from the worst to the best.
enum Band { HOSTILE, UNFRIENDLY, NEUTRAL, FRIENDLY, ALLIED }

## The names of `Band`, for logs and the overlay.
const BAND_NAMES: Array[String] = ["Hostile", "Unfriendly", "Neutral", "Friendly", "Allied"]
## The ends of the attitude scale.
const LIMIT := 100.0

static var _builds: int

## The sides, each with its row of base attitudes toward the others.
@export var factions: Array[AiFaction] = []:
	set(value):
		factions = value
		_dirty = true
		emit_changed()
## What acts cost in attitude and who must perceive them (`AiFactions.report`).
@export var events: Array[AiRelationEvent] = []
## The attitude of a pair no row names (and toward or from a faction not in the table).
@export_range(-100, 100) var default_attitude := 0:
	set(value):
		default_attitude = value
		_dirty = true

@export_group("Bands")
## At or under this, Hostile (attacks on sight).
@export_range(-100, 100) var hostile_at := -60
## At or under this, Unfriendly (watches, does not attack).
@export_range(-100, 100) var unfriendly_at := -20
## At or over this, Friendly (helps, never shoots at).
@export_range(-100, 100) var friendly_at := 20
## At or over this, Allied (follows, shares what it knows).
@export_range(-100, 100) var allied_at := 60
## How far past a band's line toward Neutral a value goes before the band is left (Hostile is
## entered at -60 and left at -40 with 20).
@export_range(0, 100) var hysteresis := 20

@export_group("Change")
## Attitude points a minute the current value drifts back toward the base.
@export_range(0.0, 600.0, 0.5, "suffix:/min") var recovery_per_minute := 10.0

## A number no other table and no earlier build of this one has, new each time the arrays are
## built (a faction added or renamed): a member's cached faction index is good while it matches.
var version := 0

var _dirty := true
var _count := 0
var _index: Dictionary[StringName, int] = {}
var _base := PackedFloat32Array()
var _current := PackedFloat32Array()
var _band := PackedByteArray()
var _drifting := false


## The index of faction `id` in the table, or -1.
func index_of(id: StringName) -> int:
	if _dirty:
		_ensure()
	return _index.get(id, -1)


## The faction with `id`, or null.
func faction(id: StringName) -> AiFaction:
	var at := index_of(id)
	return factions[at] if at >= 0 else null


## The event with `id`, or null.
func event(id: StringName) -> AiRelationEvent:
	for each in events:
		if each != null and each.id == id:
			return each
	return null


## How faction `a` feels about faction `b` now, -100 to 100.
func attitude(a: StringName, b: StringName) -> float:
	return attitude_at(index_of(a), index_of(b))


## How faction `a` feels about `b` at their base, before any event.
func base_attitude(a: StringName, b: StringName) -> float:
	var i := index_of(a)
	var j := index_of(b)
	if i < 0 or j < 0:
		return float(default_attitude)
	return _base[i * _count + j]


## The band of `a` toward `b` (`Band`), with its hysteresis.
func band(a: StringName, b: StringName) -> int:
	return band_at(index_of(a), index_of(b))


## True when `a` is Hostile toward `b`.
func is_hostile(a: StringName, b: StringName) -> bool:
	return band_at(index_of(a), index_of(b)) == Band.HOSTILE


## The attitude by faction index (`index_of`); -1 is a faction not in the table.
func attitude_at(i: int, j: int) -> float:
	if _dirty:
		_ensure()
	if i < 0 or j < 0:
		return float(default_attitude)
	return _current[i * _count + j]


## The band by faction index (`index_of`): one byte read.
func band_at(i: int, j: int) -> int:
	if _dirty:
		_ensure()
	if i < 0 or j < 0:
		return band_of(default_attitude)
	return _band[i * _count + j]


## The band a value falls in with no history (a personal grudge, a faction not in the table).
func band_of(value: float) -> int:
	if value <= hostile_at:
		return Band.HOSTILE
	if value <= unfriendly_at:
		return Band.UNFRIENDLY
	if value < friendly_at:
		return Band.NEUTRAL
	if value < allied_at:
		return Band.FRIENDLY
	return Band.ALLIED


## The band a value falls in when the pair was in `previous`: a band farther from Neutral is
## entered at its line, a band nearer Neutral only `hysteresis` past it.
func band_after(previous: int, value: float) -> int:
	var raw := band_of(value)
	if previous == Band.NEUTRAL or raw == previous:
		return raw
	if previous < Band.NEUTRAL:
		if raw < previous:
			return raw
		var held := band_of(value - hysteresis)
		return maxi(held, previous) if held < Band.NEUTRAL else raw
	if raw > previous:
		return raw
	var kept := band_of(value + hysteresis)
	return mini(kept, previous) if kept > Band.NEUTRAL else raw


## Sets `a`'s current attitude toward `b` (a mission's script); the band follows.
func set_attitude(a: StringName, b: StringName, value: float) -> void:
	var i := index_of(a)
	var j := index_of(b)
	if i < 0 or j < 0:
		push_warning("AiRelations: no faction %s or %s in the table" % [a, b])
		return
	_write(i, j, value)
	attitude_changed.emit(i, j)


## Moves `a`'s attitude toward `b` by `delta` when at least one witness perceived the act; an act
## nobody perceived (`witnesses` 0) changes nothing. Returns whether it changed.
func add_attitude(a: StringName, b: StringName, delta: float, witnesses := 1) -> bool:
	if witnesses <= 0 or is_zero_approx(delta):
		return false
	var i := index_of(a)
	var j := index_of(b)
	if i < 0 or j < 0:
		return false
	_write(i, j, _current[i * _count + j] + delta)
	attitude_changed.emit(i, j)
	return true


## Drifts every current attitude toward its base by `recovery_per_minute` for `seconds`. Free
## while nothing is off its base.
func recover(seconds: float) -> void:
	_ensure()
	if not _drifting or seconds <= 0.0:
		return
	var step := recovery_per_minute * seconds / 60.0
	_drifting = false
	for at in _current.size():
		var now := _current[at]
		if now == _base[at]:
			continue
		_write(at / _count, at % _count, move_toward(now, _base[at], step))
		_drifting = _drifting or _current[at] != _base[at]


## A copy to play (what `AiFactions` makes): the rows are copied too, so an event or a live edit
## of the copy never reaches the file loaded from disk, which every level shares.
func copy() -> AiRelations:
	var made := duplicate() as AiRelations
	var rows: Array[AiFaction] = []
	for each in factions:
		var row := each.duplicate() as AiFaction if each != null else null
		if row != null:
			row.attitudes = each.attitudes.duplicate()
		rows.append(row)
	made.factions = rows
	made.events = events.duplicate()
	made.reset()
	return made


## Puts every pair back at its base (a new match).
func reset() -> void:
	_dirty = true
	_ensure()


## The whole current table, for a late joiner: the count, then one signed byte a pair.
func encode_all() -> PackedByteArray:
	_ensure()
	var bytes := PackedByteArray()
	bytes.resize(1 + _current.size())
	bytes.encode_u8(0, _count)
	for at in _current.size():
		bytes.encode_s8(1 + at, roundi(_current[at]))
	return bytes


## One pair's change, as a server sends it: `a`'s index, `b`'s index, the value as a signed byte.
func encode_change(i: int, j: int) -> PackedByteArray:
	var bytes := PackedByteArray([i, j, 0])
	bytes.encode_s8(2, roundi(attitude_at(i, j)))
	return bytes


## Applies `encode_all()` or `encode_change()` bytes on a client (its colours follow the bands).
func apply(bytes: PackedByteArray) -> void:
	_ensure()
	if bytes.size() == 3:
		if bytes[0] < _count and bytes[1] < _count:
			_write(bytes[0], bytes[1], bytes.decode_s8(2))
		return
	if bytes.is_empty() or bytes[0] != _count or bytes.size() != 1 + _count * _count:
		push_warning("AiRelations: the table sent does not match this one")
		return
	for at in _current.size():
		_write(at / _count, at % _count, bytes.decode_s8(1 + at))


func _write(i: int, j: int, value: float) -> void:
	var at := i * _count + j
	_current[at] = clampf(value, -LIMIT, LIMIT)
	if _current[at] != _base[at]:
		_drifting = true
	var previous := _band[at]
	var now := band_after(previous, _current[at])
	if now == previous:
		return
	_band[at] = now
	band_changed.emit(factions[i].id, factions[j].id, previous, now)


# Builds the arrays from the rows; an edit to a row moves the base and keeps how far each current
# value is from it.
func _ensure() -> void:
	if not _dirty:
		return
	_dirty = false
	_builds += 1
	version = _builds
	_count = factions.size()
	_index.clear()
	for at in _count:
		var each := factions[at]
		if each == null:
			continue
		_index[each.id] = at
		if not each.changed.is_connected(_on_faction_changed):
			each.changed.connect(_on_faction_changed)
	_base.resize(_count * _count)
	_current.resize(_count * _count)
	_band.resize(_count * _count)
	_drifting = false
	for i in _count:
		for j in _count:
			var at := i * _count + j
			_base[at] = _row_value(i, j)
			_current[at] = _base[at]
			_band[at] = band_of(_base[at])


func _row_value(i: int, j: int) -> float:
	var row := factions[i]
	var column := factions[j]
	if row == null or column == null:
		return float(default_attitude)
	return clampf(float(row.attitudes.get(column.id, default_attitude)), -LIMIT, LIMIT)


func _on_faction_changed() -> void:
	if _dirty:
		return
	var offsets := PackedFloat32Array()
	offsets.resize(_current.size())
	for at in _current.size():
		offsets[at] = _current[at] - _base[at]
	var size := _current.size()
	_dirty = true
	_ensure()
	if _current.size() != size:
		return
	for at in size:
		if offsets[at] != 0.0:
			_write(at / _count, at % _count, _base[at] + offsets[at])
