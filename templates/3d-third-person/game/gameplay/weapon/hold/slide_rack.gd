class_name SlideRack
extends Resource
## Where the left hand is on a pistol's slide through the rack clip (kit #1081): the hand bone's
## way over the slide in the weapon's space (to it, closed on it, back with it, off its rear), how
## far the slide travels, and the shares of the clip at which the hand lets go of its support
## grip, closes on the slide, pulls it back, lets it go and is back on the support grip.
##
## The clip (`pistol/Pistol_Rack`) keys the whole body and both arms, with the left hand on the
## slide of the mannequin it was made on. On a body with other arms the same rotations miss the
## slide (the male's upper arms are 5 cm longer), so whatever plays the clip reaches the left hand
## to `hand_place()` by `hand_weight()` with a `HoldArm`, as `WeaponHold` reaches the
## `SupportHand` marker, and moves the weapon's `Slide` node by `travel * slide_pull()`. The
## fingers are the clip's own. Nothing here is typed: `assets/animation/pistol/build_pistol_rack.py`
## writes the numbers and `tools/hold/write_slide_rack.gd` the file. Cosmetic, never sent over a
## network.

## The clip these shares are of.
@export var clip: StringName = &"pistol/Pistol_Rack"
## The left hand bone's place in the weapon's space while it grips the closed slide.
@export var hand := Transform3D.IDENTITY
## How far the slide runs back, in the weapon's space.
@export var travel := Vector3(0.045, 0.0, 0.0)
## Where the left elbow points while the hand is over the slide, in the model's space.
@export var elbow := Vector3(0.75, 1.2, 0.05)

@export_group("The hand's way")
## The left hand bone's place in the weapon's space, at even steps of the clip from the share
## `places_from` to the share `places_to`: over the slide, closed on it, back with it and off its
## rear (the clip's own left hand on the mannequin it was keyed on).
@export var places: Array[Transform3D] = []
@export var places_from := 0.0
@export var places_to := 1.0
## Between these shares the reach takes the hand from the clip's arm onto its way.
@export var reach := Vector2(0.16, 0.25)
## Between these it gives the hand back to the clip's arm.
@export var away := Vector2(0.6, 0.77)

@export_group("Shares of the clip")
## Between these the left hand lets go of its support grip (`SupportHand`).
@export var leave := Vector2(0.036, 0.089)
## Between these it closes on the slide; from the second it is on it.
@export var grip := Vector2(0.25, 0.34)
## Between these it pulls the slide back.
@export var pull := Vector2(0.375, 0.482)
## Between these it lets the slide go and opens.
@export var release := Vector2(0.482, 0.536)
## The share of the clip the slide takes to run home once it is let go.
@export var slam := 0.036
## Between these the hand comes onto its support grip again.
@export var back := Vector2(0.91, 0.964)


## How far the left hand is on its support grip (1 at the clip's ends, 0 while it racks).
func support_weight(share: float) -> float:
	return maxf(1.0 - smoothstep(leave.x, leave.y, share), smoothstep(back.x, back.y, share))


## How far the left hand is held on its way over the slide (the rest is the clip's own arm).
func hand_weight(share: float) -> float:
	return smoothstep(reach.x, reach.y, share) * (1.0 - smoothstep(away.x, away.y, share))


## Whether the hand is closed on the slide at a share of the clip (from the grip to the letting go).
func is_gripping(share: float) -> bool:
	return share >= grip.y - 0.0001 and share <= release.x + 0.0001


## How far back the slide is along `travel`, 0 to 1: with the gripping hand until it lets go, then
## home within `slam`.
func slide_pull(share: float) -> float:
	if share <= release.x:
		return smoothstep(pull.x, pull.y, share)
	return clampf(1.0 - (share - release.x) / maxf(slam, 0.0001), 0.0, 1.0)


## The left hand bone's place in the weapon's space at a share of the clip.
func hand_place(share: float) -> Transform3D:
	if places.size() < 2:
		return hand
	var at := (share - places_from) / maxf(places_to - places_from, 0.0001) * (places.size() - 1)
	at = clampf(at, 0.0, places.size() - 1.0)
	var index := mini(floori(at), places.size() - 2)
	return places[index].interpolate_with(places[index + 1], at - index)
