class_name RackStage
extends RefCounted
## A mannequin racking the pistol's slide (kit #1081), posed by hand on a `HoldStage`: the rack
## clip at a share of its length, the hold's own right hand, the left hand on its support grip at
## the clip's ends (the hold, told it is at a reload's end), reached to the slide by a `HoldArm`
## while it racks (`SlideRack`), and the pistol's `Slide` node moved with it. A test or a capture
## then measures the hands on the weapon (`stage.contact`, taken again with the slide where it
## is). What plays the clip in the game does the same three things.

const RACK := "res://gameplay/weapon/hold/pistol_slide_rack.tres"
## The parts of the left hand that hold the slide: the palm on its top, the four fingertips on its
## right side and the thumb on its left. None may be more than `HandContact.MAX_FLOAT` off it.
const SLIDE_CONTACTS: Array[String] = [
	"palm", "index_tip", "middle_tip", "ring_tip", "pinky_tip", "thumb_tip"
]

var stage: HoldStage
var rack: SlideRack
var slide: Node3D
var arm: HoldArm
## With the reach off, the left hand is the clip's own arm (what the reach is for).
var reach_on := true

var _slide_rest := Vector3.ZERO


## Builds the stage under `holder` (a node of a running tree) with the mannequin `model`.
static func make(holder: Node, model: String) -> RackStage:
	var made := RackStage.new()
	made.stage = HoldStage.make(holder, model)
	made.rack = load(RACK) as SlideRack
	made.slide = made.stage.pistol.find_child("Slide", true, false) as Node3D
	made._slide_rest = made.slide.position
	# The hold makes its modifiers a frame later; the reach to the slide comes after them, so it
	# reads the right wrist as the hold turned it.
	await holder.get_tree().process_frame
	made.arm = HoldArm.new()
	made.arm.name = &"RackArm"
	made.arm.bone = made.stage.seat.bone_name
	made.arm.active = false
	made.stage.skeleton.add_child(made.arm)
	return made


## The clip's length in seconds.
func length() -> float:
	return stage.clip(rack.clip).length


## The clip's last frame (30 a second).
func frames() -> int:
	return roundi(length() * 30.0)


## Puts the rack clip at `share` of its length on the stage; `await stage.settle()` after it.
func pose(share: float) -> void:
	stage.pose(rack.clip, share * length(), 0.0, &"", [], 1.0)
	stage.hold.set(&"reload_weight", rack.support_weight(share))
	stage.hold.call(&"refresh")
	slide.position = _slide_rest + rack.travel * rack.slide_pull(share)
	var weight := rack.hand_weight(share) if reach_on else 0.0
	arm.offset = stage.pistol.transform * rack.hand_place(share)
	arm.elbow = rack.elbow
	arm.influence = weight
	arm.active = weight > 0.0
	# The slide moved: the weapon's surface is taken again.
	stage.contact.set_weapon(stage.pistol)


## How far the left hand's bone is from its place on the slide, in metres.
func reach(share: float) -> float:
	var place := stage.pistol.global_transform * rack.hand_place(share)
	return stage.bone_origin(&"hand_l").distance_to(place.origin)


func free_stage() -> void:
	slide.position = _slide_rest
	stage.free()
