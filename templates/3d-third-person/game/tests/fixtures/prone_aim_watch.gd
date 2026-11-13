class_name ProneAimWatch
extends RefCounted
## Watches a lying body's arms on every update of its skeleton while its prone aim blends in or
## out (kit #1356), read in `skeleton_updated`, after every modifier, as drawn: how low each
## hand's skin gets over the floor (`HandContact`), how far back each hand gets from its shoulder
## along the way the body faces (the arms folded under the chest put the hands 0.3 m under the
## floor and 0.2 m back), and, while the pistol shows, how low its magazine and muzzle get. The
## prone idle's and the prone aim's own reach are read at the two ends, for the fold's limit.

## How far under the floor a hand's skin may go, in metres: the prone idle's fists rest on it
## with their skin 1 mm in.
const SKIN_FLOOR := -0.01
## How far a hand may come back from its shoulder past the nearer of the two poses' own reach,
## in metres.
const FOLD := 0.03
## How low the pistol's magazine and muzzle may be while it shows, in metres.
const PISTOL_FLOOR := 0.0
## The prone aim's weight in the tree.
const PRONE_AIM := "parameters/Locomotion/prone/Aim/blend_amount"
const SIDES: Array[String] = ["r", "l"]

var body: Character
var animation: CharacterAnimation
var skeleton: Skeleton3D
var contact: HandContact
## How many updates were read with the prone aim between its two ends.
var between := 0
## The lowest each hand's skin got over the floor, by side.
var lowest_skin := {"r": INF, "l": INF}
## The least each hand reached ahead of its shoulder between the ends, and at the ends, by side.
var least_reach := {"r": INF, "l": INF}
var end_reach := {"r": INF, "l": INF}
## The lowest the pistol's magazine and muzzle got while it showed.
var lowest_pistol := INF
## The weight the hands were lowest at, by side (for the message).
var lowest_at := {"r": 0.0, "l": 0.0}


func _init(watched: Character) -> void:
	body = watched
	animation = body.get_node("Animation") as CharacterAnimation
	skeleton = (body.get_node("Model") as CharacterModel).skeleton()
	contact = HandContact.new(skeleton)


func start() -> void:
	skeleton.skeleton_updated.connect(_read)


func stop() -> void:
	if skeleton.skeleton_updated.is_connected(_read):
		skeleton.skeleton_updated.disconnect(_read)


## What went wrong, one line each (empty when nothing did); `label` names the body.
func failures(label: String) -> Array[String]:
	var found: Array[String] = []
	if between == 0:
		found.append("%s: no update was read while the prone aim blended" % label)
	for side in SIDES:
		if lowest_skin[side] < SKIN_FLOOR:
			found.append(
				(
					"%s: the %s hand's skin went %.1f mm under the floor (prone aim %.2f)"
					% [label, side, -lowest_skin[side] * 1e3, lowest_at[side]]
				)
			)
		if least_reach[side] < end_reach[side] - FOLD:
			found.append(
				(
					"%s: the %s hand came %.1f mm back from its shoulder, past the poses' %.1f"
					% [label, side, least_reach[side] * 1e3, end_reach[side] * 1e3]
				)
			)
	if lowest_pistol < PISTOL_FLOOR:
		found.append(
			"%s: the pistol showed %.1f mm under the floor" % [label, -lowest_pistol * 1e3]
		)
	return found


func _read() -> void:
	var weight: float = animation.tree.get(PRONE_AIM)
	var at_end := weight <= 0.0 or weight >= 1.0
	if at_end:
		for side in SIDES:
			end_reach[side] = minf(end_reach[side], _reach(side))
		return
	between += 1
	contact.snapshot()
	var floor_y := body.global_position.y
	var base := skeleton.global_transform.origin.y - floor_y
	for side in SIDES:
		var skin := base + contact.lowest(side)
		if skin < lowest_skin[side]:
			lowest_skin[side] = skin
			lowest_at[side] = weight
		least_reach[side] = minf(least_reach[side], _reach(side))
	var held := body.get_node_or_null("Model/PistolHeld") as Node3D
	if held != null and held.is_visible_in_tree():
		for part: String in ["Magazine", "Muzzle"]:
			var node := held.find_child(part, true, false) as Node3D
			lowest_pistol = minf(lowest_pistol, node.global_position.y - floor_y)


# How far the hand of `side` is ahead of its shoulder along the way the body faces, in metres.
func _reach(side: String) -> float:
	var ahead := Vector3(sin(body.facing), 0.0, cos(body.facing))
	return (_bone("hand_" + side) - _bone("upperarm_" + side)).dot(ahead)


func _bone(bone: String) -> Vector3:
	return (
		skeleton.global_transform * skeleton.get_bone_global_pose(skeleton.find_bone(bone)).origin
	)
