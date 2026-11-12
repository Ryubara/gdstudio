class_name SupportHandPlan
extends RefCounted
## Where the left hand is while the weapon is aimed and through a reload (kit #1031, #1051), worked
## out from three numbers the game already has: how far the weapon is aimed, how much of the body
## the reload clip holds, and the share of that clip played. `WeaponHold` asks it every frame and
## puts the answer on the arm and the fingers; it knows no node and no skeleton, so a test steps
## it by hand.
##
## The hand never goes straight on or off the weapon. It has one way, solved with the poses
## (`tools/hold/solve_pistol_hold.py`): the fingers open where the hand holds (`opened`), then the
## opened hand leaves along a straight line that passes through nothing (`off`), and only out
## there does the clip's own arm take it (`arm`). Coming on is the same way backwards, whether it
## comes for the aim or back from the magazine.
##
## A reload is these phases, by the share of the reload clip (`phase`); the shares are
## `WeaponHold`'s Reload group, the times of `Pistol_Reload`:
##
## - `HELD`, to `leave.x`: on the weapon, as while aiming;
## - `LET_GO`, `leave.x` to `leave.y`: opens its fingers, leaves along the way, then goes to the
##   clip's arm;
## - `AWAY`, `leave.y` to `reach.x`: the clip's own arm, down to the belt for the new magazine;
## - `REACH`, `reach.x` to `reach.y`: from the clip's arm to the line under the magazine, a
##   magazine's length down;
## - `INSERT`, `insert.x` to `insert.y`: up that line, the heel of the palm pushes the magazine in;
## - `SEATED`, `insert.y` to `back.x`: under the magazine;
## - `RETURN`, `back.x` to `back.y`: down off the magazine, across to the way's far end, in along
##   it, and the fingers close;
## - `HELD` again from `back.y`.
##
## Whatever moves with the hand reads `phase` and the outputs below; a new step of the reload is a
## new phase here, with its line in this list.
##
## The magazines (kit #1052) follow the same shares: the pistol's own magazine leaves the grip at
## `drop` (the reload's first sound, the magazine out), during `AWAY`; the new one is in the left
## hand from `take` (the hand down at the belt) until the end of `INSERT`, when it is the pistol's
## own again (`magazine_in_gun`, `magazine_in_hand`). At the belt the hold takes the fingers from
## the clip (`fingers`): they open (`carry` with `carry_open`) over `TAKE_CLOSE` before `take`,
## close on the magazine over `TAKE_CLOSE` after it and hold it until the grip's foot comes down
## over them, over `carry_release` of the way in, when they open off it and go to the pose under
## the magazine.

enum Phase { HELD, LET_GO, AWAY, REACH, INSERT, SEATED, RETURN }

## How far on the weapon the hand is when the hold's arm has it at the far end of its way:
## below `ARM_UNTIL` the arm reaches there from the clip's place, above `WAY_FROM` the hand comes
## in, and between the two it waits there while the other hand makes room for it (`room`).
const ARM_UNTIL := 0.3
const WAY_FROM := 0.6
## The share of the way the fingers take to open where the hand holds; the rest is the line.
const UNHOOK := 0.45
## The share of the let-go that is the way; over the rest the clip's arm takes the hand.
const LET_GO_WAY := 0.55
## The way back from the magazine, as shares of the return: down off the magazine by `BACK_DOWN`
## of the approach over the first of these, across to the way's far end over the second (opening
## the fingers), and in along the way from there to the return's end.
const BACK_DOWN := Vector2(0.0, 0.3)
const BACK_DOWN_SHARE := 0.4
const BACK_ACROSS := Vector2(0.12, 0.62)
## The share of the reload clip over which the fingers open before `take`, and close on the new
## magazine after it (the clip's fist would close through it).
const TAKE_CLOSE := 0.04

## The shares of the reload clip between which the hand lets go, comes under the magazine, pushes
## it in and goes back to the weapon (`WeaponHold`'s `reload_leave` and the rest).
var leave := Vector2(0.02, 0.1)
var reach := Vector2(0.3, 0.4)
var insert := Vector2(0.4, 0.54)
var back := Vector2(0.71, 0.88)
## The share of the reload clip at which the pistol's magazine leaves the grip, and the one at which
## the left hand takes the new one at the belt (`WeaponHold`'s `reload_drop` and `reload_take`).
var drop := 0.2
var take := 0.25
## The shares of the way in (0 the magazine's top at the well, 1 seated) over which the fingers go
## from holding the magazine to the pose under it (`WeaponHold.carry_release`, solved).
var carry_release := Vector2(0.4, 0.6)

## The reload's phase now (`HELD` when no reload plays).
var phase := Phase.HELD
## How far the hold's arm has the hand (0 the clip's own arm, 1 the hold's place).
var arm := 0.0
## How far the hand's place is the magazine's marker (0 the support marker and its way).
var at_magazine := 0.0
## How far the fingers are on the magazine pose (under the magazine) and on the opened pose.
var magazine_fingers := 0.0
var opened := 0.0
## How far along its way off the weapon the hand is (0 where it holds, 1 the way's far end).
var off := 0.0
## How far down the magazine's approach line the hand is below its place under the magazine
## (1 the whole `magazine_approach`).
var down := 0.0
## The part of `down` that is the way back off the seated magazine (0 until the return): the hold
## takes it along `WeaponHold.return_down`, the rest along the magazine's own way in.
var down_back := 0.0
## How far the hand is across from the magazine to the way's far end (0 to 1 and it bows out by
## `WeaponHold.return_clearance` between).
var across := 0.0
## How far the other hand has made room for this one (kit #1084: the right thumb lifts off the
## frame to lie on the root of the left one). It does so only while the hold's arm has this hand
## out at the far end of its way or beyond: 0 while the clip's arm has a share of the hand, 1
## before the hand comes in along its way, and back the same way.
var room := 0.0
## Whether the pistol's own magazine is in its grip (false from `drop` to the end of `INSERT`), and
## whether the new one is in the left hand (from `take` to the end of `INSERT`).
var magazine_in_gun := true
var magazine_in_hand := false
## How far the left hand's fingers are on the pose that carries the new magazine (from the grab at
## the belt until the grip's foot comes down over them), and how far that pose is opened (1 before
## the fingers close on the magazine): they hold it by `carry * (1 - carry_open)`.
var carry := 0.0
var carry_open := 0.0
## How far the hold has the left hand's fingers by itself while the clip's arm has the hand: from
## the grab at the belt on, opened (`opened`) and then closed on the magazine (`carry`).
var fingers := 0.0


## Works the plan out: `aim` how far the weapon is aimed, `weight` how much of the body the reload
## clip holds (0 no reload) and `share` the share of the reload clip played.
func update(aim: float, weight: float, share: float) -> void:
	phase = Phase.HELD
	at_magazine = 0.0
	magazine_fingers = 0.0
	down = 0.0
	down_back = 0.0
	across = 0.0
	magazine_in_gun = true
	magazine_in_hand = false
	carry = 0.0
	carry_open = 0.0
	fingers = 0.0
	# How far the hand is on the weapon, along its one way: 0 the clip's arm has it, `WAY_FROM`
	# the hold's arm has it at the way's far end, 1 it holds. Aiming is that number as it is, and
	# a reload blends its own with it by its weight, so the hand is on the way whatever the blend.
	var on := aim
	var magazine_arm := 0.0
	if weight > 0.0:
		phase = phase_at(share)
		_magazines(weight, share)
		var on_reload := 0.0
		if share < reach.x:
			# Letting go: the way first, then the clip's arm.
			var gone := clampf(inverse_lerp(leave.x, leave.y, share), 0.0, 1.0)
			on_reload = (
				lerpf(1.0, WAY_FROM, smoothstep(0.0, LET_GO_WAY, gone))
				* (1.0 - smoothstep(LET_GO_WAY, 1.0, gone))
			)
		else:
			# The hold has the hand from the reach to the end: under the magazine, then back.
			var returned := clampf(inverse_lerp(back.x, back.y, share), 0.0, 1.0)
			var inserted := smoothstep(insert.x, insert.y, share)
			across = smoothstep(BACK_ACROSS.x, BACK_ACROSS.y, returned)
			magazine_arm = smoothstep(reach.x, reach.y, share) * weight
			at_magazine = 1.0 - across
			magazine_fingers = 1.0 if across < 1.0 else 0.0
			down_back = BACK_DOWN_SHARE * smoothstep(BACK_DOWN.x, BACK_DOWN.y, returned)
			down = 1.0 - inserted + down_back
			if across >= 1.0:
				# At the way's far end: the other hand makes room, then in along the way.
				on_reload = lerpf(ARM_UNTIL, 1.0, smoothstep(BACK_ACROSS.y, 1.0, returned))
		on = lerpf(aim, on_reload, weight)
	arm = maxf(clampf(on / ARM_UNTIL, 0.0, 1.0), magazine_arm)
	var way := 1.0 - clampf(inverse_lerp(WAY_FROM, 1.0, on), 0.0, 1.0)
	opened = smoothstep(0.0, UNHOOK, way)
	off = smoothstep(UNHOOK, 1.0, way)
	room = smoothstep(ARM_UNTIL, WAY_FROM, on)
	if at_magazine > 0.0:
		# From the magazine the fingers open as the hand crosses to the way's far end; the other
		# hand makes room once it is there.
		opened = across
		room = 0.0


# Where the two magazines are at a share of the reload clip, and how far the fingers hold the new
# one.
func _magazines(weight: float, share: float) -> void:
	magazine_in_gun = share < drop or share >= insert.y
	magazine_in_hand = share >= take and share < insert.y
	if share >= insert.y:
		return
	if share < take - TAKE_CLOSE:
		return
	fingers = weight * smoothstep(take - TAKE_CLOSE, take, share)
	# The fingers let go of the magazine as they took it: they open off it over the first half of
	# `carry_release`, then go to the pose under the magazine over the second.
	var inserted := smoothstep(insert.x, insert.y, share)
	var middle := 0.5 * (carry_release.x + carry_release.y)
	carry_open = maxf(
		1.0 - smoothstep(take, take + TAKE_CLOSE, share),
		smoothstep(carry_release.x, middle, inserted) if share >= insert.x else 0.0
	)
	carry = weight * (1.0 - smoothstep(middle, carry_release.y, inserted))


## The reload's phase at a share of the reload clip.
func phase_at(share: float) -> Phase:
	if share >= back.y:
		return Phase.HELD
	# Each phase with the share it ends at, in order.
	var ends: Array[float] = [leave.x, leave.y, reach.x, reach.y, insert.y, back.x]
	for index in ends.size():
		if share < ends[index]:
			return index as Phase
	return Phase.RETURN
