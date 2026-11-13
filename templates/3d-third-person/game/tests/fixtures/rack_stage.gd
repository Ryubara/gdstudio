class_name RackStage
extends RefCounted
## A body racking the pistol's slide (kit #1081), posed by hand on a `HoldStage`: the rack clip at
## a share of its length, and the hold told the rack is at that share (`WeaponHold.rack_weight`,
## `rack_share`, `rack_lock`), as the game's `RackLayer` tells it (kit #1337). The hold does the
## rest with the body's own `SlideRack`, as in the game: the left hand on its support grip at the
## clip's ends, reached to the slide by its rack arm while it racks, the rack's fingers put on and
## the pistol's `Slide` node moved with it, the carried arm kept in. A test or a capture then
## measures the hands on the weapon (`stage.contact`, taken again with the slide where it is).

const RACK := "res://gameplay/weapon/hold/pistol_slide_rack.tres"
## The parts of the left hand that hold the slide: the palm on its top, the four fingertips on its
## right side and the thumb on its left. None may be more than `HandContact.MAX_FLOAT` off it.
const SLIDE_CONTACTS: Array[String] = [
	"palm", "index_tip", "middle_tip", "ring_tip", "pinky_tip", "thumb_tip"
]

var stage: HoldStage
var rack: SlideRack
var slide: Node3D
## The hold's reach to the slide and the rack's fingers (`WeaponHold.rack_modifiers()`).
var arm: HoldArm
var fingers: HandPoseModifier
## With the reach off, the left hand is the clip's own arm (what the reach is for).
var reach_on := true
## With the fingers off, they are the clip's own: the ones of the body the clip was keyed on.
var fingers_on := true
## How far back along the rack's travel the slide stands as the rack starts (0 closed; the game's
## empty pistol has it locked back, `WeaponHold.rack_lock`).
var lock := 0.0

var _slide_rest := Vector3.ZERO


## Builds the stage under `holder` (a node of a running tree) with the body `model` (`female` or
## `male`) and the rack solved on it.
static func make(holder: Node, model: String) -> RackStage:
	var made := RackStage.new()
	made.stage = HoldStage.make(holder, model)
	made.slide = made.stage.pistol.find_child("Slide", true, false) as Node3D
	made._slide_rest = made.slide.position
	# The hold makes its modifiers a frame later. It is refreshed by `pose()` alone, so the reach
	# and the fingers a test turns off stay off until the next pose.
	await holder.get_tree().process_frame
	made.stage.hold.set_process(false)
	made.rack = made.stage.hold.call(&"rack_fit") as SlideRack
	var modifiers: Array[SkeletonModifier3D] = made.stage.hold.call(&"rack_modifiers")
	made.arm = modifiers[0] as HoldArm
	made.fingers = modifiers[1] as HandPoseModifier
	return made


## A lock share for the slide locked back as the game's empty pistol has it.
func locked_share() -> float:
	var travel: float = stage.hold.get(&"slide_travel")
	return travel / rack.travel.length()


## The clip's length in seconds.
func length() -> float:
	return stage.clip(rack.clip).length


## The clip's last frame (30 a second).
func frames() -> int:
	return roundi(length() * 30.0)


## Puts the rack clip at `share` of its length on the stage; `await stage.settle()` after it.
func pose(share: float) -> void:
	stage.pose(rack.clip, share * length(), 0.0, &"", [], 1.0)
	var hold := stage.hold
	hold.set(&"reload_weight", 0.0)
	hold.set(&"reload_share", 0.0)
	hold.set(&"rack_weight", 1.0)
	hold.set(&"rack_share", share)
	hold.set(&"rack_lock", lock)
	hold.call(&"refresh")
	if not reach_on:
		arm.active = false
	if not fingers_on:
		fingers.active = false
	# The slide moved: the weapon's surface is taken again.
	stage.contact.set_weapon(stage.pistol)


## How far the left hand's bone is from its place on the slide, in metres.
func reach(share: float) -> float:
	var place := stage.pistol.global_transform * rack.hand_place(share, lock)
	return stage.bone_origin(&"hand_l").distance_to(place.origin)


func free_stage() -> void:
	slide.position = _slide_rest
	stage.free()
