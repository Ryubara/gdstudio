class_name SlideRack
extends Resource
## Where one body's left hand is on a pistol's slide through the rack clip (kit #1081): the hand
## bone's way over the slide in the weapon's space (to it, closed on it, back with it, off its
## rear), its fingers closed on the slide and opened over it, how far the slide travels, and the
## shares of the clip at which the hand lets go of its support grip, closes on the slide, pulls it
## back, lets it go and is back on the support grip.
##
## The clip (`pistol/Pistol_Rack`) keys the whole body and both arms, with the left hand and its
## fingers on the slide of the body it was made on (`CharacterBodies.FEMALE`). A body with other
## arms and hands misses the slide with the same rotations, and the hold moves the pistol after
## the clip on every body, so whatever plays the clip does three things with the rack of the
## model's body (`fit()`, as `WeaponHold.fit()` chooses a `HoldFit`): it reaches the left hand to
## `hand_place()` by `hand_weight()` with a `HoldArm`, as `WeaponHold` reaches the `SupportHand`
## marker; it puts the body's fingers on with a `HandPoseModifier` (`set_fingers()`); and it moves
## the weapon's `Slide` node by `travel * slide_pull()`. Nothing here is typed:
## `assets/animation/pistol/solve_rack_hand.py` solves each body's hand,
## `assets/animation/pistol/build_pistol_rack.py` writes the numbers and
## `tools/hold/write_slide_rack.gd` the files. Cosmetic, never sent over a network.

## The clip these shares are of.
@export var clip: StringName = &"pistol/Pistol_Rack"
## The file name of the body's model this hand was solved on (`form_female.glb`).
@export var body := ""
## The left hand bone's place in the weapon's space while it grips the closed slide.
@export var hand := Transform3D.IDENTITY
## How far the slide runs back, in the weapon's space.
@export var travel := Vector3(0.045, 0.0, 0.0)
## Where the left elbow points while the hand is over the slide, in the model's space.
@export var elbow := Vector3(0.75, 1.2, 0.05)

@export_group("The hand's way")
## The left hand bone's place in the weapon's space, at even steps of the clip from the share
## `places_from` to the share `places_to`: over the slide, closed on it, back with it and off its
## rear.
@export var places: Array[Transform3D] = []
@export var places_from := 0.0
@export var places_to := 1.0
## Between these shares the reach takes the hand from the clip's arm onto its way.
@export var reach := Vector2(0.16, 0.25)
## Between these it gives the hand back to the clip's arm.
@export var away := Vector2(0.6, 0.77)

@export_group("The fingers")
## The left hand's fingers closed on the slide: the four fingers down its right side, the index
## finger on the serrations, the thumb down its left.
@export var grip_pose: HandPose
## The same hand opened, over the slide before it closes and as it lets go.
@export var open_pose: HandPose
## Between these shares the fingers go from the hold's opened hand (as they left the support
## grip) to `open_pose`.
@export var fingers_over := Vector2(0.143, 0.25)
## Between these they go back to the hold's opened hand.
@export var fingers_away := Vector2(0.607, 0.839)
## The share at which they start to close on the slide (they are closed at `grip.y`): later than
## `grip.x`, so the hand is nearly down on the slide before the thumb and the fingers come in.
@export var fingers_close := 0.286

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

@export_group("Bodies")
## The rack solved on each other body the template ships. Hands of other sizes need another
## place on the slide and other fingers (kit #1187), so `fit()` gives the one whose `body` is the
## model's file. Typed `Array[Resource]` with a `SlideRack` hint: an exported array of a named
## class leaves scripts in use at a test run's exit (kit docs, test-exit-leaks.md).
@export_custom(PROPERTY_HINT_TYPE_STRING, "24/17:SlideRack") var fits: Array[Resource] = []


## The rack of the body whose model file is `model_file` (`form_male.glb`): the one of `fits`
## solved on it, or this one.
func fit(model_file: String) -> SlideRack:
	for each in fits:
		var rack := each as SlideRack
		if rack != null and rack.body == model_file:
			return rack
	return self


## How far the left hand is on its support grip (1 at the clip's ends, 0 while it racks).
func support_weight(share: float) -> float:
	return maxf(1.0 - smoothstep(leave.x, leave.y, share), smoothstep(back.x, back.y, share))


## How far the left hand is held on its way over the slide (the rest is the clip's own arm).
func hand_weight(share: float) -> float:
	return smoothstep(reach.x, reach.y, share) * (1.0 - smoothstep(away.x, away.y, share))


## Whether the hand is closed on the slide at a share of the clip (from the grip to the letting go).
func is_gripping(share: float) -> bool:
	return share >= grip.y - 0.0001 and share <= release.x + 0.0001


## How far the fingers are from the hold's opened hand toward `open_pose`, 0 to 1.
func fingers_opened(share: float) -> float:
	var over := smoothstep(fingers_over.x, fingers_over.y, share)
	return over * (1.0 - smoothstep(fingers_away.x, fingers_away.y, share))


## How far the fingers are closed on the slide (`grip_pose`), 0 to 1.
func fingers_closed(share: float) -> float:
	var closing := smoothstep(minf(fingers_close, grip.y - 0.0001), grip.y, share)
	return closing * (1.0 - smoothstep(release.x, release.y, share))


## Puts this body's fingers for a share of the clip on `fingers`, a `HandPoseModifier` that runs
## after the hold's: `let_go` (the hold's own opened hand, `WeaponHold.open_pose`) where the hand
## has just left the support grip, opened over the slide, closed on it, and nothing where the hold
## has the hand on its support grip.
func set_fingers(fingers: HandPoseModifier, let_go: HandPose, share: float) -> void:
	if fingers.pose != let_go:
		fingers.pose = let_go
	fingers.second = open_pose
	fingers.second_weight = fingers_opened(share)
	fingers.open = grip_pose
	fingers.open_weight = fingers_closed(share)
	fingers.influence = 1.0 - support_weight(share)
	fingers.active = let_go != null and fingers.influence > 0.0


## How far back the slide is along `travel`, 0 to 1: with the gripping hand until it lets go, then
## home within `slam`. `lock` is how far back it stands when the rack starts (0 closed; an empty
## pistol's slide locked back, `WeaponHold.slide_travel` over the travel, kit #1337): the hand
## closes on it there and pulls it the rest of the way, the slide never coming forward before it
## is let go.
func slide_pull(share: float, lock := 0.0) -> float:
	if share <= release.x:
		return maxf(lock, smoothstep(pull.x, pull.y, share))
	return clampf(1.0 - (share - release.x) / maxf(slam, 0.0001), 0.0, 1.0)


## The left hand bone's place in the weapon's space at a share of the clip. While the hand grips,
## it is its place on the closed slide moved by exactly what the slide has moved: between two of
## `places` the slide eases and a straight line does not, which slid the fingers 2.5 mm along the
## serrations at the half frames. With the slide locked back by `lock` (`slide_pull()`), the way
## to it and the grip are that much further back until the hand lets go, where the slide is at
## the end of its travel either way.
func hand_place(share: float, lock := 0.0) -> Transform3D:
	if is_gripping(share):
		return Transform3D(hand.basis, hand.origin + travel * slide_pull(share, lock))
	var place := hand
	if places.size() >= 2:
		var span := maxf(places_to - places_from, 0.0001)
		var at := clampf(
			(share - places_from) / span * (places.size() - 1), 0.0, places.size() - 1.0
		)
		var index := mini(floori(at), places.size() - 2)
		place = places[index].interpolate_with(places[index + 1], at - index)
	if share < release.x:
		place.origin += travel * lock
	return place
