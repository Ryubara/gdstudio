class_name RifleStage
extends HoldStage
## A mannequin holding the rifle the way the loadout builds it (kit #889), posed by hand: the
## model slot with a mannequin and `rifle_held.tscn` (the `TwoHandHold`) under it, with no
## `Player` and no animation tree, so a test or a capture puts an exact frame of a locomotion
## clip on the skeleton, says how far the rifle is up, where the view points and how far a reload
## is, and measures the hands on the rifle (`HandContact`) after the hold's modifiers ran.

const RIFLE_HELD := "res://gameplay/weapon/rifle_held.tscn"
## The parts that hold the rifle in each hand: none may be more than `HandContact.MAX_FLOAT` off
## it. The right hand's index finger is one of them on the trigger and along the magazine well
## alike. Its thumb bears on the grip's left rear by its middle bone: the grip is 4.3 cm deep, so
## the thumb's tip lies forward past its edge (4 to 5 mm off the receiver). Its palm has a limit
## of its own (`RIFLE_GRIP_PALM_FLOAT`).
const RIFLE_RIGHT_CONTACTS: Array[String] = [
	"index_tip",
	"middle_mid",
	"middle_tip",
	"ring_mid",
	"ring_tip",
	"pinky_mid",
	"pinky_tip",
	"thumb_mid",
]
## How far the right palm's skin may be off the grip, in metres. The two mannequins' palms differ
## by 6.5 mm on this grip (the female's is the hollower), and one place of the hand bone serves
## both: the male's palm is pressed 1.4 mm in, the female's is then 5.1 mm off.
const RIFLE_GRIP_PALM_FLOAT := 0.006
const RIFLE_LEFT_CONTACTS: Array[String] = [
	"index_mid",
	"index_tip",
	"middle_mid",
	"middle_tip",
	"ring_mid",
	"ring_tip",
	"pinky_mid",
	"pinky_tip",
	"thumb_tip",
	"palm",
]
## The parts of the left hand that hold the magazine during the reload.
const RIFLE_MAGAZINE_CONTACTS: Array[String] = [
	"index_tip", "middle_tip", "ring_tip", "thumb_tip", "palm"
]

## The rifle scene under the hold's `Pivot` (its near level is what `contact` measures against).
var rifle: Node3D


## Builds the stage under `holder` (a node of a running tree) with the mannequin `model`
## (`female` or `male`).
static func make_rifle(holder: Node, model: String) -> RifleStage:
	var stage := RifleStage.new()
	holder.add_child(stage)
	stage.slot = CharacterModel.new()
	stage.add_child(stage.slot)
	stage.slot.add_child((load(MODELS[model]) as PackedScene).instantiate())
	stage.skeleton = stage.slot.skeleton()
	stage.hold = (load(RIFLE_HELD) as PackedScene).instantiate()
	stage.slot.add_child(stage.hold)
	stage.rifle = stage.hold.get_node(^"Pivot/Rifle") as Node3D
	stage.contact = HandContact.new(stage.skeleton)
	stage.contact.set_weapon(stage.rifle.get_node(^"Near") as Node3D)
	stage.skeleton.skeleton_updated.connect(stage._on_skeleton_updated)
	return stage


## Puts `clip_name` at `time` on the skeleton with the rifle `aim` of the way up to the shoulder
## (0 the low ready), the view `pitch` degrees up, a reload `reload` of the way through (below 0:
## none) and a switch that has the rifle `lowered` of the way down.
func pose_rifle(
	clip_name: StringName, time: float, aim := 0.0, pitch := 0.0, reload := -1.0, lowered := 0.0
) -> void:
	var held := hold as TwoHandHold
	held.posed_aim = aim
	held.posed_pitch = pitch
	held.posed_reload = reload
	held.posed_lowered = lowered
	var kept := hold
	# `pose()` speaks to a pistol's hold; this one is told above.
	hold = null
	pose(clip_name, time)
	hold = kept
	held.refresh()


## How far the bone of the hand of `side` (`r` or `l`) is from its place on the rifle, in metres.
func hand_gap(side: String) -> float:
	var target := rifle.get_node("RightHandTarget" if side == "r" else "LeftHandTarget") as Node3D
	return bone_origin("hand_" + side).distance_to(target.global_position)
