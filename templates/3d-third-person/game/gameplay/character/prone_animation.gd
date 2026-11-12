class_name ProneAnimation
extends RefCounted
## What `CharacterAnimation` does for a lying body beyond its tree, kept apart so the tree's script
## stays one size: how much of the prone pose is the crawl and how fast and which way it plays,
## the weapon put away while the fists carry the body, and a model's own prone clips. Cosmetic
## only: it reads the `Character` and is never stepped or sent.

## The ground speed over which a lying body is crawling, m/s.
const CRAWL_START_SPEED := 0.02

## How much of the prone pose is the crawl (0 the idle, 1 the crawl).
var crawl_share := 0.0
## True while the weapon is put away.
var stowed := false

# The `prone` library the scene holds, put back for a model with no library of its own.
var _shared: AnimationLibrary


## Eases `crawl_share` toward the crawl while the body moves and back to the idle while it lies
## still, over `blend_time`: in time, not by the speed, so a slow crawl (aiming, a light push, a
## slow tuning) plays the whole crawl and no half-planted limb slides.
func step_crawl_share(speed: float, blend_time: float, delta: float) -> float:
	var moving := 1.0 if speed > CRAWL_START_SPEED else 0.0
	crawl_share = move_toward(crawl_share, moving, delta / maxf(blend_time, 0.001))
	return crawl_share


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


## Hides the model of the weapon in the hands (`hold.view` under `model`) while `away`, and shows
## it again after; the loadout shows the model of a weapon switched to while lying, so it is
## hidden again.
func stow_view(model: Node3D, hold: WeaponDef, away: bool) -> void:
	if model != null and hold != null and not hold.view.is_empty():
		var view := model.get_node_or_null(hold.view) as Node3D
		if view != null and (away != stowed or (away and view.visible)):
			view.visible = not away
	stowed = away


## Gives `player` the prone library `libraries` names for `rig`'s scene file, or the scene's
## shared one. Only in the game: a library swapped in the editor would be saved with the scene.
func use_model_clips(player: AnimationPlayer, rig: Node3D, libraries: Dictionary) -> void:
	_shared = swap_library(player, rig, CharacterClips.LIBRARY_PRONE, libraries, _shared)


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
