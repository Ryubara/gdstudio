class_name ProneAnimation
extends RefCounted
## What `CharacterAnimation` does for a lying body beyond its tree, kept apart so the tree's script
## stays one size: the prone state's own blend tree (the idle, the crawl, and the prone aim over
## them from the upper body up), how much of the prone pose is the crawl and how fast and which
## way it plays, the prone aim's share, look and shot kick, the weapon put away while the fists
## carry the body, and a model's own prone clips. Cosmetic only: it reads the `Character` and is
## never stepped or sent.

## The ground speed over which a lying body is crawling, m/s.
const CRAWL_START_SPEED := 0.02
## The prone state's parameters, from the state's own path (`parameters/Locomotion/prone/`).
const MOVE := "Move/blend_amount"
const CRAWL_PACE := "CrawlPace/scale"
const IDLE_PACE := "IdlePace/scale"
const AIM := "Aim/blend_amount"
const AIM_POSE := "AimPose/blend_position"

## How much of the prone pose is the crawl (0 the idle, 1 the crawl).
var crawl_share := 0.0
## True while the weapon is put away.
var stowed := false
## How much of the upper body the prone aim holds now (0 none, 1 all of it).
var aim_share := 0.0
## Where the prone aim is on its look axis, in degrees (up is positive), the shot kick included.
var aim_look := 0.0
## How far the body lies with a weapon that has a prone aim (`lying()`), as of the last frame.
var lies := 0.0

# The `prone` library the scene holds, put back for a model with no library of its own.
var _shared: Dictionary[StringName, AnimationLibrary] = {}
# What is left of the last shot's kick (1 just fired, 0 none).
var _kick := 0.0
# The looks the held weapon's prone down and up clips are made for (`WeaponDef.prone_aim_angles`).
var _angles := Vector2(25.0, 20.0)
# The tree's parameter names for the prone state, by the state's path.
var _names: Dictionary[String, StringName] = {}


## The prone state: the prone idle and the crawl, each with its own pace, blended by `Move`, and
## over them the prone aim of `hold` (its three clips by the look) on `upper`, the upper body's
## bones. A weapon with no prone aim clip gets the idle there, with no weight.
static func build(
	idle: StringName, crawl: StringName, hold: WeaponDef, upper: Array[NodePath]
) -> AnimationNodeBlendTree:
	var blend := AnimationNodeBlendTree.new()
	blend.add_node(&"Idle", _clip(idle), Vector2(0, 0))
	blend.add_node(&"IdlePace", AnimationNodeTimeScale.new(), Vector2(200, 0))
	blend.add_node(&"Crawl", _clip(crawl), Vector2(0, 200))
	blend.add_node(&"CrawlPace", AnimationNodeTimeScale.new(), Vector2(200, 200))
	blend.add_node(&"Move", AnimationNodeBlend2.new(), Vector2(400, 100))
	var pose := AnimationNodeBlendSpace1D.new()
	var angles := hold.prone_aim_angles if hold != null else Vector2(25.0, 20.0)
	pose.min_space = -maxf(angles.x, 0.1)
	pose.max_space = maxf(angles.y, 0.1)
	pose.sync = true
	var level: StringName = hold.prone_aim_clip if has_aim(hold) else idle
	var down: StringName = hold.prone_aim_down_clip if has_aim(hold) else idle
	var up: StringName = hold.prone_aim_up_clip if has_aim(hold) else idle
	pose.add_blend_point(_clip(down if down != &"" else level), pose.min_space, -1, &"down")
	pose.add_blend_point(_clip(level), 0.0, -1, &"level")
	pose.add_blend_point(_clip(up if up != &"" else level), pose.max_space, -1, &"up")
	var aim := AnimationNodeBlend2.new()
	aim.filter_enabled = true
	for path in upper:
		aim.set_filter_path(path, true)
	blend.add_node(&"AimPose", pose, Vector2(400, 300))
	blend.add_node(&"Aim", aim, Vector2(600, 100))
	blend.connect_node(&"IdlePace", 0, &"Idle")
	blend.connect_node(&"CrawlPace", 0, &"Crawl")
	blend.connect_node(&"Move", 0, &"IdlePace")
	blend.connect_node(&"Move", 1, &"CrawlPace")
	blend.connect_node(&"Aim", 0, &"Move")
	blend.connect_node(&"Aim", 1, &"AimPose")
	blend.connect_node(&"output", 0, &"Aim")
	return blend


## True when `hold` has an aim made for a lying body.
static func has_aim(hold: WeaponDef) -> bool:
	return hold != null and hold.prone_aim_clip != &""


## How far `body` lies with a weapon that has a prone aim (0 up, or no such weapon; 1 lying): by
## this much the prone aim replaces the standing weapon layer.
func lying(body: Character, hold: WeaponDef) -> float:
	lies = smoothstep(0.0, 1.0, body.prone_amount) if has_aim(hold) else 0.0
	if has_aim(hold):
		_angles = hold.prone_aim_angles
	return lies


## Puts a frame of the prone state on `tree` (`state` is the state's parameter path): the crawl's
## share and pace, the idle's pace, and the prone aim by `aim` (how far the arm is up, times how
## far the body lies) at `look` degrees up, with what is left of a shot's kick on top.
func drive(tree: AnimationTree, state: String, paces: Vector2, aim: float, look: float) -> void:
	if _names.get("state", &"") != StringName(state):
		_names = {"state": StringName(state)}
		for part: String in [MOVE, CRAWL_PACE, IDLE_PACE, AIM, AIM_POSE]:
			_names[part] = StringName(state + part)
	aim_share = aim
	aim_look = clampf(look, -_angles.x, _angles.y)
	tree.set(_names[MOVE], crawl_share)
	tree.set(_names[CRAWL_PACE], paces.x)
	tree.set(_names[IDLE_PACE], paces.y)
	tree.set(_names[AIM], aim)
	tree.set(_names[AIM_POSE], aim_look)


## Eases `crawl_share` toward the crawl while the body moves and back to the idle while it lies
## still, over `blend_time`: in time, not by the speed, so a slow crawl (aiming, a light push, a
## slow tuning) plays the whole crawl and no half-planted limb slides.
func step_crawl_share(speed: float, blend_time: float, delta: float) -> float:
	var moving := 1.0 if speed > CRAWL_START_SPEED else 0.0
	crawl_share = move_toward(crawl_share, moving, delta / maxf(blend_time, 0.001))
	return crawl_share


## A shot was fired: true when the body lies with a prone aim, which then kicks (the muzzle
## jumps up and settles) in place of the standing shot clip.
func kick() -> bool:
	if lies > 0.5:
		_kick = 1.0
	return lies > 0.5


## Moves the kick on by `delta` and gives how far up it holds the muzzle now, in degrees: all of
## `degrees` at the shot, eased out over `time`.
func step_kick(degrees: float, time: float, delta: float) -> float:
	_kick = move_toward(_kick, 0.0, delta / maxf(time, 0.001))
	return degrees * _kick * _kick


## How fast and which way the crawl clip plays for `body` (1 its own pace; below zero
## backwards): the ground speed over `clip_speed`, the speed the clip's stride covers, signed by
## whether the body moves the way it faces.
static func crawl_pace(body: Character, clip_speed: float) -> float:
	var flat := Vector3(body.velocity.x, 0.0, body.velocity.z)
	var ahead := Vector3(sin(body.facing), 0.0, cos(body.facing))
	var pace := flat.length() / maxf(clip_speed, 0.01)
	return -pace if flat.dot(ahead) < 0.0 else pace


## How far the weapon is put away for lying (0 in the hand, 1 away): the prone clips rest the body
## on its forearms and fists, which cannot hold it. Aiming brings it back.
static func stow_share(body: Character) -> float:
	return smoothstep(0.0, 1.0, body.prone_amount) * (1.0 - body.aim_amount)


## How much of a weapon's clips a body plays for how far it lies (1 all, 0 none): less than 1 only
## for a weapon whose clips stand the trunk from the pelvis (`WeaponDef.clips_upright`, the
## rifle's). Lying, the prone clips keep the body and the weapon's hold alone carries it.
static func upright_share(body: Character, hold: WeaponDef) -> float:
	if hold == null or not hold.clips_upright or body == null:
		return 1.0
	return 1.0 - smoothstep(0.0, 1.0, body.prone_amount)


## True when `body` lies too far for `hold`'s clips to play (a reload plays no clip then).
static func lies_past_clips(body: Character, hold: WeaponDef) -> bool:
	return upright_share(body, hold) < 0.5


## True when a reload plays no clip on `body`: it lies with a prone aim, which it keeps through
## the reload (the reload clip is a standing one), or too far for `hold`'s clips.
func plays_no_reload(body: Character, hold: WeaponDef) -> bool:
	return lies > 0.5 or lies_past_clips(body, hold)


## Hides the model of the weapon in the hands (`hold.view` under `model`) while `away`, and shows
## it again after; the loadout shows the model of a weapon switched to while lying, so it is
## hidden again.
func stow_view(model: Node3D, hold: WeaponDef, away: bool) -> void:
	if model != null and hold != null and not hold.view.is_empty():
		var view := model.get_node_or_null(hold.view) as Node3D
		if view != null and (away != stowed or (away and view.visible)):
			view.visible = not away
	stowed = away


## Gives `player` the prone library (the prone aim library when `aim`) that `libraries` names for
## `rig`'s scene file, or the scene's shared one. Only in the game: a library swapped in the
## editor would be saved with the scene.
func use_model_clips(
	player: AnimationPlayer, rig: Node3D, libraries: Dictionary, aim := false
) -> void:
	var library := CharacterClips.LIBRARY_PRONE_AIM if aim else CharacterClips.LIBRARY_PRONE
	var shared := swap_library(player, rig, library, libraries, _shared.get(library))
	if shared != null:
		_shared[library] = shared


## Gives `player` the library named `library` that `libraries` holds for `rig`'s scene file, or
## `shared`, the one the scene came with. Returns that shared library (found on the first call,
## when `shared` is null), for the caller to keep and pass again.
static func swap_library(
	player: AnimationPlayer,
	rig: Node3D,
	library: StringName,
	libraries: Dictionary,
	shared: AnimationLibrary
) -> AnimationLibrary:
	if Engine.is_editor_hint() or player == null or rig == null:
		return shared
	var has := player.has_animation_library(library)
	if shared == null and has:
		shared = player.get_animation_library(library)
	var wanted: AnimationLibrary = libraries.get(rig.scene_file_path, shared)
	if wanted == null or (has and player.get_animation_library(library) == wanted):
		return shared
	if has:
		player.remove_animation_library(library)
	player.add_animation_library(library, wanted)
	return shared


static func _clip(clip: StringName) -> AnimationNodeAnimation:
	var node := AnimationNodeAnimation.new()
	node.animation = clip
	return node
