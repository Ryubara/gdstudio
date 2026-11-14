class_name ItemUse
extends Node
## Using an item that takes time (a bandage): a hotbar press starts it, the character plays the
## item's clip over its upper body with the left hand off the weapon, its sound plays, and at
## `ItemDef.use_apply_share` of `ItemDef.use_time` the item works, its effect and the one taken out
## of the bag on the same tick (`Hotbar.use`). While it runs the hands are busy: the character
## does not aim or shoot (`Character.hands_busy`), and a second press uses nothing, so one press is
## one item. An item with no `use_time` works at the press, as before.
##
## The rules that cut a use short are the template's and each is a switch below: sprinting,
## pressing fire, aim, jump, melee or reload, a weapon switch, lying down or getting up, a hit
## that takes health, and death (always). A use cut short before its item works changes nothing.
##
## It counts its time in the body's own ticks and reads only the command the body's step took
## (`Character.last_command`, whose `use_place` is the press): offline it runs in
## `_physics_process` after the character's step (it is the character's child); a server and a
## predicting client step it themselves right after the body (`step`, `stepped_by_owner`).
## Online (gdstudio #1386) the server's copy is the `AUTHORITY`; the user's own screen
## (`PREDICT`) starts and cuts the use at once and plays it, but the item works only when the
## server says so (`server_applied`), and another player's body on a screen (`PUPPET`) plays what
## the server's USE events say. The clip, the sound and the sign are each screen's, never sent.

## A use began: `item` from hotbar `place`, taking `seconds`.
signal started(place: int, item: ItemDef, seconds: float)
## The item worked: its effect landed and one left the bag.
signal applied(place: int, item: ItemDef)
## The use ran to its end.
signal finished(place: int, item: ItemDef)
## The use was cut short; `reason` names the rule (`sprint`, `fire`, `hit`, `died`...).
signal cancelled(place: int, item: ItemDef, reason: StringName)
## A press of `place` started nothing (dead, sprinting, run out, of no use now); a press during a
## use is not one.
signal refused(place: int)

## Who decides a use on this peer.
enum Role {
	AUTHORITY,  ## Offline and on the server: the rules run here and the item works here.
	PREDICT,  ## The user's own screen online: starts and cuts at once, the server applies.
	PUPPET,  ## Another player's body on a screen: plays the server's events, decides nothing.
}

## The reasons a use is cut short, by their number on the wire (a USE event's detail).
const CUT_REASONS: Array[StringName] = [
	&"cancelled",
	&"died",
	&"hit",
	&"sprint",
	&"fire",
	&"aim",
	&"jump",
	&"weapon",
	&"prone",
	&"refused",
]

@export_group("Nodes")
## The character that uses the item. Empty: the parent.
@export var character: Character
## The places the items come from. Empty: the character's `Hotbar`.
@export var hotbar: Hotbar
## Plays the item's `use_sound`, at the character (the player's `UseSound`, a 3D node under the
## body: under this plain node it would sit at the world's origin). Empty: no sound.
@export var sound: AudioStreamPlayer3D

@export_group("Cut short by")
## Sprinting.
@export var cancel_on_sprint := true
## A press of the fire button (the shot follows once the weapon is up).
@export var cancel_on_fire := true
## A press of the aim button (an aim already held when the use began is only lowered).
@export var cancel_on_aim := true
## A jump.
@export var cancel_on_jump := true
## A melee blow, a reload or a weapon switch.
@export var cancel_on_weapon_press := true
## Lying down or getting up.
@export var cancel_on_prone := true
## A hit that takes health.
@export var cancel_on_hit := true

## Who decides a use here (`NetClient` and `PlayerPuppet` set it online).
var role := Role.AUTHORITY
## On: whoever steps the body calls `step` right after it (a server, a predicting client), and
## `_physics_process` does nothing.
var stepped_by_owner := false
## The number of the command that started the running use (online, the USE events name it).
var start_seq := 0

var _place := -1
var _item: ItemDef
var _elapsed := 0.0
var _applied := false
# The apply tick passed on a screen that waits for the server's word (`PREDICT`, `PUPPET`).
var _apply_due := false
var _aim_was := false
var _prone_was := false
var _hit_this_tick := false


func _ready() -> void:
	if character == null:
		character = get_parent() as Character
	if hotbar == null and character != null:
		hotbar = Hotbar.of(character)
	if character != null:
		character.took_hit.connect(_on_took_hit.unbind(2))
		character.died.connect(_on_died)
	# Warm the hotbar's sounds now, so the first use does not decode in its frame.
	if hotbar != null and sound != null:
		for start in hotbar.start_items:
			if start != null and start.use_sound != null:
				DecodedSounds.decoded(start.use_sound)


## The `ItemUse` of `node`: `node` itself, or its first child that is one. Null when it has none.
static func of(node: Object) -> ItemUse:
	if node is ItemUse:
		return node
	var parent := node as Node
	if parent == null:
		return null
	for child in parent.get_children():
		if child is ItemUse:
			return child
	return null


## True while a use runs.
func is_using() -> bool:
	return _item != null


## The item being used, or null.
func item() -> ItemDef:
	return _item


## How far the running use is, 0 at the press to 1 at its end (0 with none).
func progress() -> float:
	if _item == null or _item.use_time <= 0.0:
		return 0.0
	return clampf(_elapsed / _item.use_time, 0.0, 1.0)


## True once the running use's item has worked (online, once the server said so).
func has_applied() -> bool:
	return _applied


## Uses hotbar `place`: an item that takes time starts a use, one that does not works at once.
## Refused (false) while a use runs, while the character cannot (dead, sprinting) or when the
## hotbar refuses the place (empty, run out, of no use now). A `PUPPET` never starts one itself.
func request(place: int) -> bool:
	if hotbar == null or character == null or is_using() or role == Role.PUPPET:
		return false
	var wanted := hotbar.item_at(place)
	if wanted == null or not wanted.takes_time():
		return _use_at_once(place)
	if character.is_dead() or (cancel_on_sprint and character.is_sprinting()):
		refused.emit(place)
		return false
	if not _may_use(place):
		hotbar.use_refused.emit(place, wanted)
		refused.emit(place)
		return false
	start_seq = character.last_command.seq
	_begin(place, wanted)
	return true


## Plays a use the server says another player began (a `PUPPET`'s, gdstudio #1386): the clip,
## the free hand and the sound of the item at `place`, ended by its time or a later event.
func play_remote(place: int, command_seq: int) -> void:
	var wanted := hotbar.item_at(place) if hotbar != null else null
	if wanted == null or not wanted.takes_time() or character == null or character.is_dead():
		return
	if is_using():
		cancel(&"cancelled")
	start_seq = command_seq
	_begin(place, wanted)


## The server applied the use begun on command `command_seq` (its low 16 bits): the running use
## of that command says `applied`. The health and the count come with the event (`ClientItems`).
func server_applied(command_seq: int) -> void:
	if _is_running(command_seq) and not _applied:
		_applied = true
		applied.emit(_place, _item)


## The server cut short, or refused, the use begun on command `command_seq`: the running use of
## that command ends here too (a use this screen ended already, or a later one, is not touched).
func server_cancelled(command_seq: int, reason: StringName) -> void:
	if _is_running(command_seq):
		cancel(reason)


## The number of `reason` on the wire (0, `cancelled`, for one not in `CUT_REASONS`).
static func reason_code(reason: StringName) -> int:
	return maxi(CUT_REASONS.find(reason), 0)


## The reason numbered `code` on the wire.
static func reason_of(code: int) -> StringName:
	return CUT_REASONS[code] if code >= 0 and code < CUT_REASONS.size() else &"cancelled"


## Cuts the running use short for `reason`. Nothing happens when none runs.
func cancel(reason: StringName = &"cancelled") -> void:
	if _item == null:
		return
	var place := _place
	var was := _item
	_end()
	_stop_presentation()
	cancelled.emit(place, was, reason)


func _physics_process(delta: float) -> void:
	if not stepped_by_owner:
		step(delta)


## One tick of the body, right after its step: the running use is cut, moves on or works; an idle
## one starts on the command's press (`PlayerCommand.use_place`).
func step(delta: float) -> void:
	if character == null:
		return
	if _item == null:
		_remember()
		var pressed := character.last_command.use_place
		if pressed >= 0 and role != Role.PUPPET:
			request(pressed)
		return
	var reason := &"" if role == Role.PUPPET else _cancel_reason()
	_hit_this_tick = false
	_remember()
	if reason != &"":
		cancel(reason)
		return
	_elapsed += delta
	if not _applied and not _apply_due and _elapsed >= _item.use_time * _item.use_apply_share:
		if role != Role.AUTHORITY:
			_apply_due = true
		elif not hotbar.use(_place):
			cancel(&"refused")
			return
		else:
			_applied = true
			applied.emit(_place, _item)
	if _elapsed >= _item.use_time:
		var place := _place
		var was := _item
		_end()
		finished.emit(place, was)


func _begin(place: int, wanted: ItemDef) -> void:
	_place = place
	_item = wanted
	_elapsed = 0.0
	_applied = false
	_apply_due = false
	_hit_this_tick = false
	character.hands_busy = true
	started.emit(place, wanted, wanted.use_time)
	_play_presentation(wanted)


func _end() -> void:
	_place = -1
	_item = null
	_elapsed = 0.0
	_applied = false
	_apply_due = false
	if character != null:
		character.hands_busy = false


# An item with no use time: it works at once where the bag is this peer's word; a predicting
# screen only checks it could (the server's APPLIED brings the health and the count).
func _use_at_once(place: int) -> bool:
	if role == Role.PREDICT:
		return _may_use(place)
	start_seq = character.last_command.seq
	if not hotbar.use(place):
		refused.emit(place)
		return false
	applied.emit(place, hotbar.item_at(place))
	return true


# Whether `place` would do something now: the hotbar's own word, or, on a screen whose hotbar is
# not the word (an online client), the same test on its copy of the bag and the health.
func _may_use(place: int) -> bool:
	if hotbar.authoritative:
		return hotbar.can_use(place)
	var wanted := hotbar.item_at(place)
	if wanted == null or not wanted.is_usable() or hotbar.count_at(place) <= 0:
		return false
	return wanted.use_effect.can_apply(hotbar.user)


func _is_running(command_seq: int) -> bool:
	return _item != null and (start_seq & 0xFFFF) == (command_seq & 0xFFFF)


# The first rule the last step broke, or empty.
func _cancel_reason() -> StringName:
	var command := character.last_command
	var rules := {
		&"died": character.is_dead(),
		&"hit": cancel_on_hit and _hit_this_tick,
		&"sprint": cancel_on_sprint and character.is_sprinting(),
		&"fire": cancel_on_fire and command.fire_pressed,
		&"aim": cancel_on_aim and command.aim and not _aim_was,
		&"jump": cancel_on_jump and command.jump_pressed,
		&"weapon": cancel_on_weapon_press and _weapon_pressed(command),
		&"prone": cancel_on_prone and character.prone != _prone_was,
	}
	for reason: StringName in rules:
		if rules[reason]:
			return reason
	return &""


func _weapon_pressed(command: PlayerCommand) -> bool:
	return (
		command.melee_pressed
		or command.reload_pressed
		or command.next_weapon_pressed
		or command.previous_weapon_pressed
		or command.unarmed_pressed
	)


func _remember() -> void:
	if character != null:
		_aim_was = character.last_command.aim
		_prone_was = character.prone


func _on_took_hit() -> void:
	_hit_this_tick = true


func _on_died() -> void:
	cancel(&"died")


# What each screen shows of a use, worked out here and never sent: the clip, the free hand, the
# sound.
func _play_presentation(wanted: ItemDef) -> void:
	var animation := _animation()
	if animation != null and wanted.use_clip != &"":
		animation.play_clip(wanted.use_clip, wanted.use_time, true)
	for hold in _holds():
		if hold is WeaponHold:
			(hold as WeaponHold).free_hand(wanted.use_time)
		elif hold is TwoHandHold:
			(hold as TwoHandHold).free_hand(wanted.use_time)
	if sound != null and wanted.use_sound != null:
		# Decoded once to PCM: an Ogg Vorbis start reads its headers again (`DecodedSounds`).
		sound.stream = DecodedSounds.decoded(wanted.use_sound)
		sound.play()


func _stop_presentation() -> void:
	var animation := _animation()
	if animation != null and animation.is_acting():
		animation.stop_clip()
	for hold in _holds():
		if hold is WeaponHold:
			(hold as WeaponHold).take_hand_back()
		elif hold is TwoHandHold:
			(hold as TwoHandHold).take_hand_back()
	if sound != null:
		sound.stop()


func _animation() -> CharacterAnimation:
	if character == null:
		return null
	for child in character.get_children():
		if child is CharacterAnimation:
			return child
	return null


# The character's weapon holds (the pistol's beside the model, the rifle's made under it when it is
# taken), found by type at each start and end: each lets the left hand go for the use's time.
func _holds() -> Array[Node]:
	var found: Array[Node] = []
	if character == null:
		return found
	var queue: Array[Node] = [character]
	while not queue.is_empty():
		var node: Node = queue.pop_back()
		if node is WeaponHold or node is TwoHandHold:
			found.append(node)
		elif not node is Skeleton3D:
			queue.append_array(node.get_children())
	return found
