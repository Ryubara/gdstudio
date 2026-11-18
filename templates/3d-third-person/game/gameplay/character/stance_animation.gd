class_name StanceAnimation
extends RefCounted
## The stance changes between standing and crouching drawn by their own clips (gdstudio #1576):
## a body at rest that crouches plays `GaitSettings.stand_to_crouch_clip` and one that stands
## plays `crouch_to_stand_clip`, carried over the whole body (`ActionLayer.play_carried()`: no
## cross-fade, the momentum blend takes the drawn pose into the clip and the clip's last pose into
## the state under it), with the arms left to the weapon layer while a weapon is held. Getting up
## from lying ends on the crouch idle (`prone/Prone_To_Crouch`), so a body that stands up from
## there goes on into the crouch's own rise. Before, the crouch at rest was the momentum blend
## alone (the body dropped 0.45 m in about six ticks) and the end of getting up was the one-shot's
## 0.1 s fade-out from the crouch idle into the standing idle.
##
## Only the drawn pose waits: the capsule, the speed and the state change on their tick
## (`Character._update_crouch`), and a move asked for, a jump, a fall, a slide or lying down ends
## the clip on the frame it comes, the momentum blend carrying the pose on from there. A moving body
## changes stance by the momentum blend alone, as before. `CharacterAnimation` owns one and drives
## it every frame before the tree. Cosmetic, never sent.

# Whether the body was crouched on the last frame.
var _crouched := false
# True when the body stood up while getting up's clip still played: it rises once that clip ends.
var _stand_after := false


## The clip that changes the stance to `crouch` (true: down) by `settings`.
static func clip_for(settings: GaitSettings, crouch: bool) -> StringName:
	return settings.stand_to_crouch_clip if crouch else settings.crouch_to_stand_clip


## True when `clip` is one of `settings`' stance clips.
static func is_stance_clip(settings: GaitSettings, clip: StringName) -> bool:
	return (
		clip != &""
		and (clip == settings.stand_to_crouch_clip or clip == settings.crouch_to_stand_clip)
	)


## True when `body` stands still on the floor with no move asked for, upright or crouched: where a
## stance clip may play.
static func at_rest(body: Character, settings: GaitSettings) -> bool:
	if body == null or not body.is_on_floor() or body.prone_amount > 0.0:
		return false
	if body.state != Character.State.IDLE and body.state != Character.State.CROUCH:
		return false
	return (
		body.ground_speed() < settings.standing_speed
		and body.move_goal.direction(body).is_zero_approx()
	)


## True when the action clip `playing` hands over to the stand's clip the moment it ends: getting
## up's clip on a body at rest that is no longer crouched.
func follows(animation: CharacterAnimation, playing: StringName) -> bool:
	var settings := CharacterGait.settings_of(animation)
	return (
		settings.stance_clips
		and playing != &""
		and playing == animation.to_crouch_clip
		and not animation.character.crouching
		and at_rest(animation.character, settings)
	)


## Moves the layer on for a frame of `animation`, before the tree: `ended` is the carried clip the
## action layer ended this frame (`ActionLayer.tick()`), `playing` the action clip that plays now
## (`&""` for none) and `active` whether one plays.
func drive(
	animation: CharacterAnimation, ended: StringName, playing: StringName, active: bool
) -> void:
	var body := animation.character
	var settings := CharacterGait.settings_of(animation)
	var crouched := body.crouching
	var changed := crouched != _crouched
	_crouched = crouched
	if not settings.stance_clips:
		_stand_after = false
		return
	var rest := at_rest(body, settings)
	var mine := active and is_stance_clip(settings, playing)
	if ended == animation.to_crouch_clip and ended != &"":
		var stand := _stand_after or not crouched
		_stand_after = false
		if stand and not crouched and rest:
			_play(animation, settings, false)
		return
	if changed:
		if active and playing == animation.to_crouch_clip:
			_stand_after = not crouched
		elif rest and (not active or mine):
			_play(animation, settings, crouched)
		return
	if mine and not rest:
		animation.actions.stop(animation)


func _play(animation: CharacterAnimation, settings: GaitSettings, crouch: bool) -> void:
	var clip := clip_for(settings, crouch)
	var player := animation.animation_player
	if player == null or not player.has_animation(clip):
		return
	var time := settings.stand_to_crouch_time if crouch else settings.crouch_to_stand_time
	animation.actions.play_carried(animation, clip, time)
	animation.action_started.emit(clip)
