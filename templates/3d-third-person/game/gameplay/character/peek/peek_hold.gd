class_name PeekHold
extends RefCounted
## How much a lean holds the trunk and the head through an upper-body action (gdstudio #1575).
##
## The actions over the upper body (a shot, a reload, the slide's rack, a melee blow or a punch, an
## item's use, a weapon switch) are clips that own every bone from `spine_01` up, the neck and the
## head among them, and the aim layer gives way to them (its spine turn and its level head fade out
## by the action's share). Upright that is the action's look; leaning it took the head off the
## lean's line: the bend rolls whatever the clips leave, so the pistol's reload dropped the head 3
## to 4 cm and turned it 70 degrees toward the gun. A peek is for looking past cover, so while the
## body leans the action is drawn on the arms: `PeekModifier` keeps the spine's, the neck's and the
## head's turns from the clips as they were when the action began, and `AimLayer` keeps its spine
## turn, its level head and its sight turn as they were.
##
## `share` is how far the body leans (eased) while the hold is on. It comes on whole in the update
## an action begins (its clip has no weight yet, so nothing moves), stays on until the action is
## over and the aim it lowered (an item's use) is back up, then lets go over the
## `PeekTuning.action_release_time`, so whatever changed under it meanwhile (a crouch, the aim's
## pitch) is eased into. A switch holds the old weapon's pose while it goes down and lets go as the
## new one comes up (the loadout's lowering), since the new weapon has its own stance. `PeekLayer`
## owns one and steps it once a frame. A pose on each machine from what the body already has:
## never sent.

const _P_INSIDE := StringName("parameters/%s/internal_active" % ActionLayer.NODE)
const _P_FADING_IN := StringName("parameters/%s/fade_in_remaining" % ActionLayer.NODE)
const _P_FADING_OUT := StringName("parameters/%s/fade_out_remaining" % ActionLayer.NODE)
## The share an upper-body action clip counts for in its first update, before its fade gives it any.
const _FIRST := 0.01
## How near the aim must come back to where it was before the action before the hold lets go.
const _AIM_BACK := 0.02

## The share the lean holds the trunk and the head by now (0 none, 1 all of it).
var share := 0.0

# The hold is on (an action began and is not over, or the aim it lowered is not back).
var _engaged := false
# A switch's new weapon is coming up: the hold goes with the loadout's lowering.
var _drawing := false
# The weapon held when the hold came on.
var _held_before: WeaponDef
# How much of the hold is left as it lets go (1 on, 0 gone).
var _envelope := 0.0
# The aim pose's weight before the action, and in the last update with no action.
var _aim_before := 0.0
var _aim_last := 0.0
var _frame := -1
var _use: ItemUse


## Steps the hold for this frame (once a frame: a second call in the same frame changes nothing)
## and returns `share`.
func step(body: Character, animation: CharacterAnimation) -> float:
	var frame := Engine.get_process_frames()
	if frame == _frame:
		return share
	_frame = frame
	var delta := body.get_process_delta_time() if body != null else 0.0
	share = 0.0
	if body == null or animation == null or animation.tree == null:
		_reset()
		return share
	var tuning := body.peek_tuning
	var lean := absf(body.peek_motion.drawn())
	if tuning == null or not tuning.action_hold or lean <= 0.0:
		_reset()
		return share
	# The aim as the aim layer's head reads it (the fists have no aim pose).
	var aim := maxf(animation.pistol_weights().y, body.aim_amount)
	var action := action_share(body, animation)
	if action <= 0.0 and _using(body):
		# From the use's first tick: its chest turn (`UseTurn`) comes before the tree shows the clip.
		action = _FIRST
	var held := animation.held_definition()
	if action > 0.0 and not _engaged and not _drawing:
		_engaged = true
		_held_before = held
		_aim_before = maxf(_aim_last, aim)
	if _engaged and held != _held_before:
		# A switch: the weapon after it has its own stance, so the hold goes as it comes up.
		_engaged = false
		_drawing = true
	if _drawing:
		var lowered := body.loadout.lowered_amount() if body.loadout != null else 0.0
		_envelope = minf(_envelope, lowered)
		_drawing = lowered > 0.0
	elif _engaged and action <= 0.0:
		# The command's buttons: an item's use holds `aim_held` off while it runs.
		var aiming := body.last_command.aim or body.last_command.fire
		_engaged = aiming and aim < _aim_before - _AIM_BACK
	if not _engaged and not _drawing:
		_aim_last = aim
	if _engaged:
		_envelope = 1.0
	elif not _drawing and _envelope > 0.0:
		var time := tuning.action_release_time
		_envelope = maxf(_envelope - delta / time, 0.0) if time > 0.0 else 0.0
	share = smoothstep(0.0, 1.0, lean) * smoothstep(0.0, 1.0, _envelope)
	return share


## How much of the upper body an action holds now (0 none, 1 all of it): the most of the reload's,
## the rack's, the melee blow's, an upper-body action clip's (an item's use) and a weapon switch's
## (the loadout's lowering), and all of it while a shot's clip plays.
static func action_share(body: Character, animation: CharacterAnimation) -> float:
	if animation.is_shooting():
		return 1.0
	var tree := animation.tree
	var held := maxf(animation.reload_progress().x, animation.rack.progress().x)
	held = maxf(held, animation.melee.share(tree))
	if animation.is_acting() and not animation.is_acting(true):
		# Some of it from the first update: the clip has no weight yet, but its `UseTurn` turns the
		# chest at once.
		held = maxf(held, maxf(_upper_action_share(animation), _FIRST))
	if body.loadout != null:
		held = maxf(held, body.loadout.lowered_amount())
	return clampf(held, 0.0, 1.0)


# True while `body` uses an item (its `ItemUse`, looked up once).
func _using(body: Character) -> bool:
	if _use == null or not is_instance_valid(_use) or _use.get_parent() != body:
		_use = ItemUse.of(body)
	return _use != null and _use.is_using()


func _reset() -> void:
	_engaged = false
	_drawing = false
	_envelope = 0.0
	_aim_last = 0.0


# How much of the upper body the action one-shot holds while it plays an upper-body clip (an item's
# use, a hit crouched): it fades in and out over `action_blend_time`.
static func _upper_action_share(animation: CharacterAnimation) -> float:
	var tree := animation.tree
	var fade := maxf(animation.action_blend_time, 0.001)
	if not tree.get(_P_INSIDE):
		return clampf(float(tree.get(_P_FADING_OUT)) / fade, 0.0, 1.0)
	return clampf(1.0 - float(tree.get(_P_FADING_IN)) / fade, 0.0, 1.0)
