class_name RackLayer
extends RefCounted
## The slide's rack after a reload of an empty magazine (kit #1337): a one-shot on the upper body,
## over the reload's, that plays the held weapon's `WeaponDef.rack_clip` (the pistol's
## `pistol/Pistol_Rack`) at its own speed as the reload clip ends, and says how far it is
## (`progress()`) for the `WeaponHold`, which puts the left hand on the slide and moves the slide
## by it (`SlideRack`). The `CharacterAnimation` owns one (`rack`) and steps it every frame.
##
## The rack clip starts on the reload clip's last frame, so it comes in over the reload's last
## moments (`FADE_IN`, `START_EARLY`), and the reload's one-shot is told not to fade out for that
## reload: the two blend between the same poses and the body never passes the pose under them
## (with both fading the arms sank a quarter of the way to the carry). It is cosmetic and never
## sent: the rounds go in at the end of the weapon's `reload_time`, as with no rack, and a shot or
## a switch cuts the rack short. A reload with rounds left, or lying down, has none. The reload's
## last sound (the slide) is left to the rack, which plays it where the hand lets the slide go
## (`WeaponDef.rack_sound_at`).

## The tree's nodes: the one-shot and its clip.
const NODE := "Rack"
const CLIP := "RackClip"
## Seconds the rack takes to come over the reload's end (short: the two clips meet on one pose,
## and the hand leaves its grip 0.03 s into the rack), and to leave the body at its own end or when
## a shot cuts it short.
const FADE_IN := 0.03
const FADE_OUT := 0.2
## Seconds before the reload clip's end, past `FADE_IN`, at which the rack starts: it is all in
## before the reload's one-shot ends, whichever frame that falls on.
const START_EARLY := 0.04

const _P_ACTIVE := StringName("parameters/%s/active" % NODE)
const _P_REQUEST := StringName("parameters/%s/request" % NODE)
const _P_FADING_IN := StringName("parameters/%s/fade_in_remaining" % NODE)
const _P_FADING_OUT := StringName("parameters/%s/fade_out_remaining" % NODE)
const _P_INSIDE := StringName("parameters/%s/internal_active" % NODE)
const _P_AT := StringName("parameters/%s/current_position" % CLIP)
const _P_LENGTH := StringName("parameters/%s/current_length" % CLIP)

## True from a reload of an empty magazine that will end with the rack until the rack starts (or
## the reload is cut short).
var pending := false

var _animation: CharacterAnimation
var _clip_node: AnimationNodeAnimation
var _reload: AnimationNodeOneShot
var _reload_fade_out := 0.0
var _reload_seconds := 0.0
# The rack was asked for and the tree has not said it ended: only then is the tree read.
var _playing := false
var _seen := false
var _sounded := false
# The weapon whose reloads this follows (connected once).
var _heard: Weapon


## Adds the one-shot to `root` over `below` (the reload's one-shot, whose fade-out it takes off for
## a reload that ends with the rack), filtered to `upper`, and returns its name for the next layer
## to go over. The clip node holds the held weapon's rack clip, or `idle` with none.
func add_to(
	animation: CharacterAnimation,
	root: AnimationNodeBlendTree,
	below: StringName,
	upper: Array[NodePath],
	idle: StringName
) -> StringName:
	_animation = animation
	var shot := AnimationNodeOneShot.new()
	shot.fadein_time = FADE_IN
	shot.fadeout_time = FADE_OUT
	shot.filter_enabled = true
	for path in upper:
		shot.set_filter_path(path, true)
	var hold := animation.held_definition()
	var clip: StringName = hold.rack_clip if hold != null and hold.rack_clip != &"" else idle
	_clip_node = AnimationNodeAnimation.new()
	_clip_node.animation = clip
	root.add_node(CLIP, _clip_node, Vector2(1200, 1100))
	root.add_node(NODE, shot, Vector2(1250, 0))
	root.connect_node(NODE, 0, below)
	root.connect_node(NODE, 1, CLIP)
	_reload = root.get_node(below) as AnimationNodeOneShot
	_reload_fade_out = _reload.fadeout_time if _reload != null else 0.0
	pending = false
	_playing = false
	var weapon := animation.character.weapon if animation.character != null else null
	# Once a weapon: the tree is built again on every change of the held definition.
	if weapon != null and weapon != _heard and not Engine.is_editor_hint():
		weapon.reload_started.connect(_on_reload_started)
		weapon.reload_cancelled.connect(stop)
		weapon.fired.connect(func(_shot: Projectile) -> void: stop())
		weapon.melee_started.connect(func(_blow: int) -> void: stop())
		_heard = weapon
	return NODE


## Moves the rack on for a frame: starts it over the reload's end when one is pending, and plays
## the slide's sound where the hand lets the slide go.
func step() -> void:
	var tree := _animation.tree if _animation != null else null
	if tree == null or _clip_node == null:
		return
	if pending:
		var reload := _animation.reload_progress()
		var weapon := _animation.character.weapon
		if _animation.prone_hold_share() > 0.5:
			# Lain down since: the prone reload has no rack.
			_restore_reload()
		elif _animation.is_reloading():
			if (1.0 - reload.y) * _reload_seconds <= FADE_IN + START_EARLY:
				_start()
		elif weapon == null or not weapon.is_reloading():
			_start()
	if not _playing:
		return
	var now := progress()
	if not _seen and now.x > 0.0:
		_seen = true
	elif _seen and not tree.get(_P_ACTIVE):
		_playing = false
		if not pending:
			_restore_reload()
		return
	var hold := _animation.held_definition()
	if not _sounded and hold != null and now.y >= hold.rack_sound_at:
		_sounded = true
		_play_slide(_animation.character.weapon, hold)


## Where the rack clip is: x how much of the upper body it holds now (0 none, 1 all of it: it fades
## in and out), y the share of the clip that has played. Zero while it does not play.
func progress() -> Vector2:
	var tree := _animation.tree if _animation != null else null
	if not _playing or tree == null or not tree.get(_P_ACTIVE):
		return Vector2.ZERO
	var weight := 1.0 - float(tree.get(_P_FADING_IN)) / FADE_IN
	if not tree.get(_P_INSIDE):
		weight = float(tree.get(_P_FADING_OUT)) / FADE_OUT
	var length: float = tree.get(_P_LENGTH)
	var share := float(tree.get(_P_AT)) / length if length > 0.0 else 1.0
	return Vector2(clampf(weight, 0.0, 1.0), clampf(share, 0.0, 1.0))


## True from a reload that will end with the rack until the rack has left the body (asked for,
## the tree may not have started it yet).
func is_racking() -> bool:
	return pending or _playing


## Cuts the rack short (a shot, a blow, a switch): it fades out, and the hold hands the slide back
## at rest as the hand leaves it. A reload cut short has none to come.
func stop() -> void:
	_restore_reload()
	var tree := _animation.tree if _animation != null else null
	if _playing and tree != null and tree.tree_root != null:
		tree.set(_P_REQUEST, AnimationNodeOneShot.ONE_SHOT_REQUEST_FADE_OUT)


func _on_reload_started(seconds: float) -> void:
	# A reload started over a rack (rounds left in the reserve after the last one) takes the body.
	stop()
	var weapon := _animation.character.weapon
	var hold := _animation.held_definition()
	var player := _animation.animation_player
	# The reload clip that plays is the standing one (not the prone reload) and the rack fits it.
	pending = (
		hold != null
		and hold.rack_clip != &""
		and weapon.ammo is int
		and weapon.ammo == 0
		and _animation.prone_hold_share() <= 0.5
		and player != null
		and player.has_animation(hold.rack_clip)
		and player.has_animation(hold.reload_clip)
	)
	weapon.reload_steps_held = 1 if pending else 0
	_reload_seconds = seconds
	if _reload != null:
		_reload.fadeout_time = 0.0 if pending else _reload_fade_out


func _start() -> void:
	pending = false
	var hold := _animation.held_definition()
	if hold == null or hold.rack_clip == &"":
		return
	_clip_node.animation = hold.rack_clip
	_animation.tree.set(_P_REQUEST, AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)
	_playing = true
	_seen = false
	_sounded = false


# The reload's one-shot fades out again as it does with no rack to follow.
func _restore_reload() -> void:
	pending = false
	if _reload != null:
		_reload.fadeout_time = _reload_fade_out


# The reload's last sound (the slide's), which this reload left to the rack, on the weapon's own
# reload player at the muzzle (`Weapon.reload_steps_held`).
static func _play_slide(weapon: Weapon, hold: WeaponDef) -> void:
	var player := weapon.get_node_or_null(^"%ReloadSound") as AudioStreamPlayer3D
	if not weapon.effects or player == null or not player.is_inside_tree():
		return
	if hold.reload_sounds.is_empty() or hold.reload_sounds[-1] == null:
		return
	player.stream = DecodedSounds.decoded(hold.reload_sounds[-1])
	var at: Node3D = (
		weapon.muzzle if weapon.muzzle != null and weapon.muzzle.is_inside_tree() else weapon
	)
	player.global_position = at.global_position
	player.play()
