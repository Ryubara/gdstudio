class_name WeaponLoadout
extends Node
## The weapons a character carries and the switch between them: numbered `slots` of
## `WeaponDef`s, and `unarmed` (the fists), a weapon of its own. It gives its `weapon` node the
## definition in the hands, keeps the magazine and the reserve of each slot while it is put away,
## shows the model of the one in the hands (the definition's `view` under `model`) and fills a
## reserve from a `Pickup` whose `item_id` is the definition's `ammo_item`. `give()` adds a weapon
## it does not carry yet in a new slot (a `WeaponPickup` calls it), or only its rounds when it
## does.
##
## A switch takes the old weapon's `holster_time` (it goes down and cannot fire or reload; a
## reload under way is cut short and gives nothing), then the new one's `draw_time` (it comes up,
## ready at the end). Asking for another weapon during a switch goes there instead: from the
## way down it carries on down, from the way up it goes down again from where it is.
##
## It is stepped by its character (`tick()`, before the weapon), never by a clock, and its state is
## in the character's step state (`CharacterState.loadout`), so a server and a predicting client
## switch on the same tick. Nothing of it is cosmetic: what is in the hands is gameplay.

## The weapon in the hands changed (in the middle of a switch, when the old one is down).
signal weapon_changed(definition: WeaponDef)
## A switch toward `definition` began.
signal switch_started(definition: WeaponDef)
## A switch ended: the weapon is up and ready.
signal switch_finished(definition: WeaponDef)
## `give()` put a weapon the loadout did not carry in a new slot, `slot`.
signal weapon_added(definition: WeaponDef, slot: int)
## The carried weapons changed while the game runs (`give()` added one or put rounds on one that is
## not in the hands, or a restored step state took one back): a screen that lists `slots` and
## their rounds (the inventory) redraws. Rounds of the weapon in the hands are its `ammo_changed`.
signal slots_changed

enum Phase { READY, HOLSTER, DRAW }
## What `give()` did.
enum Given { NOTHING, AMMO, WEAPON }

## The slot number of the empty hands.
const UNARMED := -1

@export_group("Nodes")
## The weapon node that fires what is in the hands.
@export var weapon: Weapon
## The character's `Model` slot, under which each definition's `view` (its model in the hand) and
## `muzzle` are found. Empty (a body with no model, as a server loads): no model is shown and the
## weapon fires from beside its shooter.
@export var model: Node3D
## The character whose pickups fill the reserves (its `item_collected`). Empty: the parent.
@export var character: Character

@export_group("Weapons")
## The weapons carried, in order: next and previous go through them, then the empty hands.
@export var slots: Array[WeaponDef] = []
## The empty hands: a weapon of its own (the fists' blows). Empty: there are no empty hands.
@export var unarmed: WeaponDef
## The slot in the hands at the start (0 is the first; -1 the empty hands).
@export var start_slot := 0
## On: a weapon `give()` adds is brought out at once (an arena shooter's pickup). Off: it waits in
## its slot for next or previous.
@export var switch_to_new := true

var _held := UNARMED
var _target := UNARMED
var _phase := Phase.READY
var _phase_left := 0.0
var _last_armed := 0
## Each slot's magazine and reserve while it is put away, as [magazine, reserve].
var _kept: Array = []


func _ready() -> void:
	# Its own list: `give()` adds to it, and an array from a scene may be shared by its instances.
	slots = slots.duplicate()
	if character == null:
		character = get_parent() as Character
	if character != null:
		character.item_collected.connect(_on_item_collected)
	_kept.clear()
	for definition in slots:
		_make_view(definition)
	for definition in slots:
		_kept.append([definition.magazine_size, definition.start_reserve] if definition else [0, 0])
	var first := clampi(start_slot, UNARMED, slots.size() - 1)
	if first == UNARMED and unarmed == null:
		first = 0 if not slots.is_empty() else UNARMED
	_last_armed = maxi(first, 0)
	_target = first
	_equip(first)


## The slot in the hands (-1 for the empty hands). During a switch it is the old one until the
## middle of the switch.
func held_slot() -> int:
	return _held


## The slot a switch is going to (the held one when there is no switch).
func target_slot() -> int:
	return _target


## The definition in the hands, or null.
func held_definition() -> WeaponDef:
	return _definition(_held)


## True while a switch runs (the weapon cannot fire or reload).
func is_switching() -> bool:
	return _phase != Phase.READY


## How far the weapon is put away: 0 up and ready, 1 all the way down (the middle of a switch).
func lowered_amount() -> float:
	match _phase:
		Phase.HOLSTER:
			var time := _time_of(_held, true)
			return 1.0 - _phase_left / time if time > 0.0 else 1.0
		Phase.DRAW:
			var time := _time_of(_held, false)
			return _phase_left / time if time > 0.0 else 0.0
	return 0.0


## The magazine and the reserve of `slot`, as [magazine, reserve] (the weapon's own numbers for the
## one in the hands).
func ammo_of(slot: int) -> Array:
	if slot == _held and weapon != null and _definition(slot) != null:
		return [weapon.ammo, weapon.reserve] if _definition(slot).uses_ammo() else [0, 0]
	return _kept[slot].duplicate() if slot >= 0 and slot < _kept.size() else [0, 0]


## Switches to `slot` (-1 the empty hands). Asking for the one in the hands does nothing; asking
## during a switch goes to the new one instead.
func select(slot: int) -> void:
	if slot != UNARMED and (slot < 0 or slot >= slots.size() or slots[slot] == null):
		return
	if slot == UNARMED and unarmed == null:
		return
	if slot != UNARMED:
		_last_armed = slot
	match _phase:
		Phase.READY:
			if slot == _held:
				return
			_begin_holster(slot, 0.0)
		Phase.HOLSTER:
			if slot == _held:
				# Back up from where it is.
				_target = slot
				_phase = Phase.DRAW
				_phase_left = _time_of(_held, false) * lowered_amount()
			else:
				_target = slot
				switch_started.emit(_definition(slot))
		Phase.DRAW:
			if slot == _held:
				_target = slot
				return
			_begin_holster(slot, lowered_amount())


## Switches to the next weapon (the slots in order, then the empty hands, round again).
func next() -> void:
	select(_step_from(_target, 1))


## Switches to the previous weapon.
func previous() -> void:
	select(_step_from(_target, -1))


## Switches between the weapon and the empty hands: from a weapon to the hands, from the hands back
## to the last weapon.
func toggle_unarmed() -> void:
	if _target == UNARMED:
		select(_last_armed)
	else:
		select(UNARMED)


## Puts `amount` rounds of ammunition `item_id` in the reserve of every carried weapon that takes
## it. True when one took it.
func take_ammo(item_id: StringName, amount: int) -> bool:
	var taken := false
	for slot in slots.size():
		var definition := slots[slot]
		if definition == null or definition.ammo_item == &"" or definition.ammo_item != item_id:
			continue
		taken = true
		if slot == _held and weapon != null:
			weapon.add_ammo(amount)
		else:
			var kept: Array = _kept[slot]
			kept[1] = mini(kept[1] + amount, maxi(definition.max_reserve, kept[1]))
	return taken


## The slot that carries `definition`, or -1 when none does.
func slot_of(definition: WeaponDef) -> int:
	return slots.find(definition) if definition != null else -1


## How many more rounds the reserve of `slot` takes before it is full (0 for a weapon with no
## magazine or a slot that is not carried).
func reserve_room(slot: int) -> int:
	var definition := _definition(slot)
	if slot < 0 or definition == null or not definition.uses_ammo():
		return 0
	return maxi(definition.max_reserve - int(ammo_of(slot)[1]), 0)


## Gives the character `definition` with `rounds` rounds for its reserve. A weapon it does not
## carry goes in a new slot with a full magazine and `rounds` in the reserve (held to
## `max_reserve`), and is brought out when `switch_to_new` is on; one it carries takes only the
## rounds, up to a full reserve. Returns how it went: `GIVEN_WEAPON`, `GIVEN_AMMO` or `NOTHING`
## (it carries the weapon with a full reserve, or `definition` is null).
func give(definition: WeaponDef, rounds: int) -> Given:
	if definition == null:
		return Given.NOTHING
	var slot := slot_of(definition)
	if slot >= 0:
		var taken := mini(maxi(rounds, 0), reserve_room(slot))
		if taken <= 0:
			return Given.NOTHING
		if slot == _held and weapon != null:
			weapon.add_ammo(taken)
		else:
			_kept[slot][1] += taken
			slots_changed.emit()
		return Given.AMMO
	_make_view(definition)
	slots.append(definition)
	var reserve := clampi(rounds, 0, definition.max_reserve) if definition.uses_ammo() else 0
	_kept.append([definition.magazine_size, reserve])
	slot = slots.size() - 1
	_show_views()
	weapon_added.emit(definition, slot)
	slots_changed.emit()
	if switch_to_new:
		select(slot)
	return Given.WEAPON


## Moves the switch one physics tick on. The character calls it in its `step`, before the weapon's.
func tick(delta: float) -> void:
	if _phase == Phase.READY:
		return
	_phase_left -= delta
	while _phase != Phase.READY and _phase_left <= 0.0:
		if _phase == Phase.HOLSTER:
			_equip(_target)
			_phase = Phase.DRAW
			_phase_left += _time_of(_held, false)
			_play_draw()
		else:
			_phase = Phase.READY
			_phase_left = 0.0
			if weapon != null:
				weapon.lowered = false
			switch_finished.emit(held_definition())


## The loadout's step state in `kept`: what is held, where a switch is, each slot's ammunition and
## the weapons carried (a pickup adds one).
func save_step_state(kept: Array) -> void:
	kept.resize(7)
	kept[0] = _held
	kept[1] = _target
	kept[2] = _phase
	kept[3] = _phase_left
	kept[4] = _last_armed
	kept[5] = _kept.duplicate(true)
	kept[6] = slots.duplicate()


## Puts back what `save_step_state()` wrote.
func load_step_state(kept: Array) -> void:
	if kept.size() < 6:
		return
	if kept.size() > 6 and kept[6] != slots:
		# A weapon given after the state was saved goes again, its model with it.
		_set_views_visible(false)
		slots.assign(kept[6])
		_show_views()
		slots_changed.emit()
	if kept[0] != _held:
		_equip(kept[0])
	_target = kept[1]
	_phase = kept[2]
	_phase_left = kept[3]
	_last_armed = kept[4]
	_kept = kept[5].duplicate(true)
	if weapon != null:
		weapon.lowered = _phase != Phase.READY


func _begin_holster(slot: int, already_down: float) -> void:
	_target = slot
	_phase = Phase.HOLSTER
	_phase_left = _time_of(_held, true) * (1.0 - already_down)
	if weapon != null:
		weapon.cancel_reload()
		weapon.lowered = true
	switch_started.emit(_definition(slot))
	if _phase_left <= 0.0:
		tick(0.0)


# Puts `slot` in the hands at once: its definition and ammunition on the weapon, its model shown.
func _equip(slot: int) -> void:
	if weapon != null and _held >= 0 and _held < _kept.size() and weapon.definition != null:
		if weapon.definition.uses_ammo():
			_kept[_held] = [weapon.ammo, weapon.reserve]
	_held = slot
	var definition := _definition(slot)
	if weapon != null and definition != null:
		weapon.definition = definition
		if slot >= 0 and slot < _kept.size():
			weapon.set_ammo(_kept[slot][0], _kept[slot][1])
		weapon.muzzle = _node_under_model(definition.muzzle)
	_show_views()
	weapon_changed.emit(definition)


# Shows the model of the definition in the hands and hides every other one.
func _show_views() -> void:
	if model == null:
		return
	var shown := _node_under_model(_definition(_held).view) if _definition(_held) else null
	var all: Array[WeaponDef] = slots.duplicate()
	all.append(unarmed)
	for definition in all:
		if definition == null:
			continue
		var view := _node_under_model(definition.view) as Node3D
		if view != null:
			view.visible = view == shown


# Makes the definition's `view_scene` under `model` when the model slot has no `view` node yet
# (a weapon given by a pickup brings its model in the hand with it). It starts hidden.
func _make_view(definition: WeaponDef) -> void:
	if model == null or definition == null or definition.view_scene == null:
		return
	if definition.view.is_empty() or definition.view.get_name_count() != 1:
		return
	if model.has_node(definition.view):
		return
	var view := definition.view_scene.instantiate() as Node3D
	if view == null:
		return
	view.name = String(definition.view.get_name(0))
	view.visible = false
	model.add_child(view)


func _set_views_visible(shown: bool) -> void:
	for definition in slots:
		var view := _node_under_model(definition.view) if definition != null else null
		if view != null:
			view.visible = shown


func _node_under_model(path: NodePath) -> Node3D:
	if model == null or path.is_empty():
		return null
	return model.get_node_or_null(path) as Node3D


func _definition(slot: int) -> WeaponDef:
	if slot == UNARMED:
		return unarmed
	return slots[slot] if slot >= 0 and slot < slots.size() else null


func _time_of(slot: int, holster: bool) -> float:
	var definition := _definition(slot)
	if definition == null:
		return 0.0
	return definition.holster_time if holster else definition.draw_time


# The slot `direction` steps from `slot` in the round: the slots in order, then the empty hands.
func _step_from(slot: int, direction: int) -> int:
	var order: Array[int] = []
	for index in slots.size():
		if slots[index] != null:
			order.append(index)
	if unarmed != null:
		order.append(UNARMED)
	if order.is_empty():
		return slot
	var at := order.find(slot)
	if at < 0:
		return order[0]
	return order[posmod(at + direction, order.size())]


func _play_draw() -> void:
	if weapon != null:
		weapon.play_draw_sound()


func _on_item_collected(item_id: StringName, amount: int, _total: int) -> void:
	take_ammo(item_id, amount)
