class_name HoldStow
extends RefCounted
## A `TwoHandHold` while the body lies with its weapon put away (gdstudio #1581): the prone clips
## rest the body on its forearms and fists, so lying puts the weapon away
## (`ProneAnimation.stow_share`) and the pistol's grip fades out with it through the weapon layer's
## `Armed` weight. The rifle's hold is skeleton modifiers after the tree, which nothing faded: its
## stance, arms and fingers stayed on the hidden rifle all the way down, and its chest turn, read
## about the model's up axis, swung the other way in one tick as the trunk pitched forward past
## lying flat's half (the head 0.48 m). This is the share the hold keeps (`kept`, 1 in the hands,
## 0 put away): the same stow share the weapon layer hides the rifle by, so the hold eases out
## as the body lies down and back in as it gets up, aims or plays a reload clip, at the pace the
## prone tuning's `enter_time` and `exit_time` set; no timing of its own.

## How much of the hold stays on now (1 all of it, 0 put away for lying).
var kept := 1.0

var _animation: CharacterAnimation


## Reads how far `body`'s weapon is put away for lying this frame (`ProneAnimation.stow_share`,
## with its animation's reload clip weight, as `WeaponLayers.drive` reads it), and gives `kept`.
func step(body: Character) -> float:
	if body == null:
		kept = 1.0
		return kept
	if _animation == null or not is_instance_valid(_animation):
		_animation = body.get_node_or_null(^"Animation") as CharacterAnimation
	var reloading := 0.0
	if _animation != null and _animation.tree != null:
		reloading = _animation.reload_progress().x
	kept = 1.0 - ProneAnimation.stow_share(body, reloading)
	return kept
