class_name ServerItems
extends RefCounted
## The server's half of using an item (gdstudio #1386): the server owns every bag and every health.
## Each player's body gets the bag, the hotbar and the `ItemUse` of `body_items.tscn` (the body
## alone has none), stepped right after the body with the command it took, so a press is the
## command's `use_place` and the use runs on the server's ticks by the same rules as offline.
## What it does becomes USE events (`NetEvent.UseCode`), 8 bytes each; the clip, the sound and the
## sign are each screen's own:
##
## - STARTED (slot, place, the starting command's seq) to every other player; the user's own screen
##   started the use at the press.
## - APPLIED (the count left at the place, the health after it) to everyone: the server's heal and
##   count are the only ones.
## - CANCELLED (the reason, `ItemUse.CUT_REASONS`) to everyone: a cut the user's screen did not
##   see itself (a hit) ends it there too.
## - REFUSED to the user alone, naming the refused command: a use its screen began is taken back.
##
## `NetServer` owns one and hands it each body (`watch`) and each step (`stepped`).

## Uses started, applied, cut short and refused, since the start.
var started := 0
var applied := 0
var cancelled := 0
var refused := 0

## `func(event: NetEvent)`: to every seated player.
var tell_all := Callable()
## `func(slot: int, event: NetEvent)`: to every player but `slot`.
var tell_others := Callable()
## `func(slot: int, event: NetEvent)`: to `slot` alone.
var tell := Callable()

var _uses: Dictionary[int, ItemUse] = {}


## Gives `body` (not yet in the tree) the nodes of `items` as its own children: they find the body
## and each other in their `_ready`. A null scene gives nothing.
static func equip(body: Character, items: PackedScene) -> void:
	if items == null:
		return
	var holder := items.instantiate()
	for child in holder.get_children():
		holder.remove_child(child)
		child.owner = null
		body.add_child(child)
	holder.free()


## Takes `body` (in the tree) as `slot`'s: its `ItemUse` is stepped by `stepped`, and what it does
## becomes events.
func watch(slot: int, body: Character) -> void:
	var use := ItemUse.of(body)
	if use == null:
		return
	_uses[slot] = use
	use.stepped_by_owner = true
	use.started.connect(_on_started.bind(slot, use))
	use.applied.connect(_on_applied.bind(slot, use))
	use.cancelled.connect(_on_cancelled.bind(slot, use))
	use.refused.connect(_on_refused.bind(slot, use))


## Forgets `slot` (its body is being freed).
func forget(slot: int) -> void:
	_uses.erase(slot)


## After `slot`'s body stepped `delta` seconds: its use moves on, or starts on the command's press.
func stepped(slot: int, delta: float) -> void:
	var use: ItemUse = _uses.get(slot)
	if use != null and is_instance_valid(use):
		use.step(delta)


## `slot`'s `ItemUse`, or null.
func use_of(slot: int) -> ItemUse:
	return _uses.get(slot)


func _on_started(place: int, _item: ItemDef, _seconds: float, slot: int, use: ItemUse) -> void:
	started += 1
	_send(tell_others, slot, NetEvent.use(slot, NetEvent.UseCode.STARTED, place, use.start_seq))


func _on_applied(place: int, _item: ItemDef, slot: int, use: ItemUse) -> void:
	applied += 1
	var health := Health.of(use.character)
	var left := clampi(use.hotbar.count_at(place), 0, 0xFF)
	var event := NetEvent.use(
		slot,
		NetEvent.UseCode.APPLIED,
		place,
		use.start_seq,
		left,
		health.wire_value() if health != null else NetEvent.NO_HEALTH
	)
	if tell_all.is_valid():
		tell_all.call(event)


func _on_cancelled(place: int, _item: ItemDef, reason: StringName, slot: int, use: ItemUse) -> void:
	cancelled += 1
	var code := ItemUse.reason_code(reason)
	var event := NetEvent.use(slot, NetEvent.UseCode.CANCELLED, place, use.start_seq, code)
	if tell_all.is_valid():
		tell_all.call(event)


func _on_refused(place: int, slot: int, use: ItemUse) -> void:
	refused += 1
	var seq := use.character.last_command.seq
	var code := ItemUse.reason_code(&"refused")
	_send(tell, slot, NetEvent.use(slot, NetEvent.UseCode.REFUSED, place, seq, code))


func _send(to: Callable, slot: int, event: NetEvent) -> void:
	if to.is_valid():
		to.call(slot, event)
