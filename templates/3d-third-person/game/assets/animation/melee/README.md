# Melee clips

Six clips of the template's own for the melee blow every weapon has (kit #1254): three of the fists and three of the
pistol in the right hand, on the mannequins' rig. Godot imports `melee.glb` as an `AnimationLibrary`, like the two
packs; added to an `AnimationPlayer` under the name `melee`, the clips are `melee/Melee_Unarmed_Jab` and so on.

| File | What it is |
| --- | --- |
| `melee.glb` | The six clips (30 frames a second like the library's, in place, no loop, every bone keyed on every frame) |
| `melee_clips.json` | Each clip's length, contact time, hit window, striking bone and point, reach, and what the build measured |
| `build_melee.py` | Rebuilds both with the pinned Blender (`blender -b --factory-startup -P build_melee.py`); the same bytes |
| `render_melee.py` | The review sheets (`build_melee.py -- --render <folder>`) |
| `../limb_overlap.py` | Measures limbs passing through each other, for this build and any other clips |

## The clips

Times are seconds from the clip's start. Reach is how far the striking point is in front of the chest (the
`spine_03` joint) at contact, on the female mannequin and on the male, whose arms are longer.

| Clip | Length | Contact | Hit window | Reach (f / m) | Height | What happens |
| --- | --- | --- | --- | --- | --- | --- |
| `Melee_Unarmed_Jab` | 0.533 | 0.167 | 0.139 to 0.231 | 0.69 / 0.74 | 1.51 | The left fist straight out and back, the right fist at the jaw |
| `Melee_Unarmed_Cross` | 0.600 | 0.200 | 0.179 to 0.285 | 0.69 / 0.74 | 1.50 | The right fist through behind a 38 degree turn of the chest |
| `Melee_Unarmed_Hook` | 0.600 | 0.200 | 0.179 to 0.220 | 0.67 / 0.72 | 1.50 | The left fist round in a level arc, the bent arm carried by the chest |
| `Melee_Pistol_Whip` | 0.733 | 0.267 | 0.237 to 0.300 | 0.57 / 0.61 | 1.54 | The pistol up beside the head and down and forward, the butt leading |
| `Melee_Pistol_Backhand` | 0.700 | 0.267 | 0.248 to 0.296 | 0.60 / 0.64 | 1.65 | The pistol across to the left shoulder and out to the right, the slide's flat leading |
| `Melee_Pistol_Jab` | 0.633 | 0.233 | 0.195 to 0.340 | 0.61 / 0.65 | 1.40 | The pistol back to the ribs and driven forward and up, the butt leading |

The striking point is the middle finger's knuckle for the fists (`hand_l` for the jab and the hook, `hand_r` for the
cross) and a point of the pistol for the pistol clips (`hand_r`; `gun_points` in the json, in the `Pistol` node's
space: the middle of the grip's foot, or the slide's right flat). The hit window is the span the striking point is
within 0.1 m of where it is at contact. The swings pass through that place and are short (the hook 0.04 s, the
backhand 0.05 s); the straight blows stay near it longer. A game that wants a kinder window widens it.

## Using them

- **Upper body only.** The game plays a blow as a one-shot on `spine_01` and every bone below it, over whatever the
  legs do. So the pelvis and the legs hold the joined pose on every frame, and the whole blow is in the spine (the
  chest turns up to 46 degrees), the collarbones and the arms. The head keeps the joined pose's facing while the
  chest turns under it.
- **What they join.** The fists' clips start and end on frame 0 of the library's `Idle_Loop`, the pistol's on frame 0
  of `Pistol_Idle_Loop` (both hands on the pistol). The first and last poses are those poses to the bit. A clip leaves
  the pose at speed (the striking wrist moves at 2.0 to 4.5 m/s in the first frame) and comes back to rest on it: the
  fade in (about 0.05 s) is what eases the start.
- **The fists are closed on every frame**, the first and the last too: the fingers are the only bones that differ from
  the idle there.
- **The pistol's hand** is keyed with the fingers of the game's grip pose
  (`gameplay/weapon/hold/pistol_grip_pose.tres`) on every frame, so the hand holds a grip with or without
  `WeaponHold`. The hand bone is keyed for the game: `WeaponHold` turns the wrist under the grip after the clip (the
  `turns` of the grip pose), and with that turn the pistol sits as the sheets show it. Played without `WeaponHold`,
  the pistol is 28 degrees off.
- **The left hand is free in the pistol clips**: it leaves the pistol sideways in the first two frames, guards (the
  whip and the jab) or swings back beside the hip (the backhand), and returns sideways over the last four. Take the
  support hand's own solver off while a blow plays, and fade it back with the clip's end.
- **The carried arm's swing.** `WeaponHold` holds the carrying arm 8 degrees out from the body (`carry_arm_out`). The
  clips were measured without it; the pistol is never nearer the head or the trunk than 39 mm (the whip, frame 2), so
  a swing away from the body has room.

## What the build checks

`build_melee.py` fails, and writes nothing, when any of these is over its limit. The worst value of each is in
`melee_clips.json` (`checks`), per clip.

| Check | Limit | Worst measured |
| --- | --- | --- |
| A body part inside another, both mannequins, every frame (`limb_overlap.py`) | 5 mm | 0.0 mm |
| The pistol in the body or the body in the pistol, both mannequins, every frame (the holding hand aside) | 5 mm | 0.0 mm |
| First and last pose against the pose it joins (16 main joints) | 10 mm | 0.00 mm |
| A joint's velocity changing in one frame: wrists 6.5, elbows 6.0, shoulders 2.0, head 1.0, chest 1.0 m/s | by joint | 5.77 m/s (the hook's guard elbow), wrists 5.52 |
| A fist open: a fingertip's distance from its wrist | 105 mm | 87.9 mm (an open hand: 200) |
| An arm's length in the blow, as a share of straight (a locked elbow pops) | 0.975 | 0.972 (the backhand), the jab 0.936 |
| The wrist's bend from the forearm's line, as the game shows it | 40 degrees | 29.2 degrees |
| The striking point's reach at contact, both mannequins | 0.55 to 0.75 m | 0.573 to 0.741 m |
| The striking point's height at contact | 1.25 to 1.75 m | 1.40 to 1.65 m |
| The striking point faster into contact than after it | | 5.3 to 9.1 m/s into contact |
| The exported file played back against the solved poses | 0.5 mm | 0.001 mm |

Before the clips, the build tests the pistol check itself: the pistol as carried reads 0.0 mm, the holding hand on the
grip 3.9 mm (female) and 6.9 mm (male), a pistol pushed into the head 70 and 80 mm, and both striking points lie on
the pistol's surface.

**One thing the limits do not cover.** The library's `Pistol_Idle_Loop` wraps the left hand round the right one: on
the meshes the left hand is 26 mm inside the right hand (24 mm on the male) and, on the male, 12 mm in the grip. Two
hands that start inside each other cannot part without crossing. So for the clip's first two frames and last four
(the spans the game fades), the left arm against the right hand, forearm and pistol is held to the joined pose's own
depth and 5 mm more, not to 5 mm. The deepest there is 28.8 mm (the male, the backhand's frame 20), against 24.4 mm in
the joined pose itself. Every other pair, and these on every other frame, read 0.0 mm. In the game the left hand is
held on the pistol by `WeaponHold` until the blow starts, not by this pose.

## How they were made

Every clip is a table of keys on a few controls: the chest's turn (shared out over the three spine bones), each
collarbone, the head, and each wrist's place with the way its elbow points, the way its palm faces and the wrist's
bend. Curves through the keys give every frame, a two-bone solver turns the wrists into arm rotations, and every bone
is keyed on every frame. A hand lies along its forearm unless its bend says otherwise, so a wrist cannot be keyed
further round than a wrist goes. A guarding fist is keyed from its own shoulder in the chest's axes, so it turns
with the chest and cannot end up inside it.

The shape of a blow is the same in all six: a short wind-up (the chest turns a little the other way while the hand
goes to where the blow starts), the snap to contact over three or four frames, a follow-through of one or two frames,
and the way back.

## No mirror poses

Nothing in these clips is the same on both sides (kit `docs/tools/blender/own-animation.md#feel`). The legs and the
hips are the library's own staggered stance. Above them every side has its own numbers:

- **The guard is two guards.** The rear (right) fist sits close under the jaw, 0.26 m ahead of its shoulder and
  0.04 m over it, the elbow near the ribs. The lead (left) fist is held further out and lower (0.30 m ahead, 0.02 m
  under, 0.03 m out), the elbow away from the body. In the cross the lead fist comes back higher still (0.09 m over
  the shoulder), above the fist that goes.
- **The two fists never move together.** The guard rises a frame or two after the striking fist starts, stays up
  while the striking fist drops, and comes down three frames after it.
- **Both shoulders are keyed, each its own way.** The striking shoulder goes forward and up (9 to 16 degrees forward);
  the other is pulled back 5 to 9 degrees, and dropped 2 to 3 degrees or, in the cross and the pistol jab, shrugged
  5 degrees to cover the chin.
- **The chest tilts as well as turns** (2 to 4 degrees of roll, to a different side in the wind-up and the blow), and
  the head tips 3 to 4 degrees and turns 3 to 6 off the line instead of sitting square over it.
- **The pistol clips' left hand has its own place in each clip** on the way back: in at the ribs (the whip), low
  beside the hip (the backhand), up in front of the chest (the jab), never level with the pistol.

The front and top sheets of every clip were read for anything lined up before the file was built. Three things were:
the cross's two fists level at frame 4, both fists level on the way back in the cross and the hook (frames 12 to 14),
and the pistol and the left fist level at the waist near the end of all three pistol clips. Each has its own numbers
now.

## Research

Studied for the mechanics and the timing only; nothing was traced or copied.

- **How fast a fist goes.** Dinu and Louis measured boxers with inertial sensors: the hand at impact moves at
  8.1 m/s in a cross and 8.9 to 11.2 m/s in a hook, and a blow runs from the pelvis through the trunk and the shoulder
  to the elbow and the wrist ([Biomechanical Analysis of the Cross, Hook, and Uppercut in Junior vs. Elite
  Boxers](https://www.frontiersin.org/journals/sports-and-active-living/articles/10.3389/fspor.2020.598861/full),
  Frontiers in Sports and Active Living, 2020). Ours: the knuckle comes into contact at 8.2 m/s (jab), 9.1 m/s (cross)
  and 7.0 m/s (hook) on the female, 9.3, 10.6 and 8.0 on the male. The chest's turn leads the arm in every clip.
- **Straight or round.** The same paper describes the cross as a blow that goes forward with the body and the hook as
  a turn of the whole body that carries the arm. So the cross is keyed as a straight line of the wrist behind a turn
  of the chest, and the hook as a bent arm (the elbow at 104 degrees, level with the shoulder) that the chest's
  turn, from 14 degrees left to 34 right at contact and on to 46, swings across the front. The jab is the quick one:
  the least turn (10 degrees) and the shortest clip.
- **What the library's own punches do.** The kit's audit of the Universal Animation Library
  (`docs/tools/blender/own-animation.md#audit-clips`) measured `Punch_Jab` and `Punch_Cross`: the chest drives the
  blow (43 and 57 degrees), the hand lands in two frames, and they end 0.63 m from the idle with the hand 19 to 28 mm
  inside the head on the female. Ours end on the idle and read 0.0 mm.
- **Where a pistol is held close in.** Handgun retention training holds the pistol with the wrist high against the
  ribs on the strong side, the elbow straight back, and the other hand in close to the body
  ([Handgun Retention Shooting Positions](https://www.shootingillustrated.com/content/handgun-retention-shooting-positions),
  Shooting Illustrated). `Melee_Pistol_Jab` starts its drive from that place, and the left hand guards in close in
  all three.
- **Which part of a pistol strikes.** A hand that holds a grip has the barrel along its forearm, and a wrist bends
  about 20 to 30 degrees toward the thumb. So the butt can lead only while the forearm points up: the whip lands with
  the forearm still pointing up and the hand above the place it hits, as a hammer does, and the jab drives up from
  the elbow. The backhand turns the back of the hand to the right and lands the slide's flat. No search turned up a
  written source on striking with a pistol; these three follow from the hand and the wrist, and are checked by the
  wrist's bend (29 degrees at most) in the build.

## What they do not do

- **No step and no weight shift in the legs**: the game plays the upper body over its own legs. A blow thrown
  standing still would be stronger with a step, and that would be a full-body clip of its own.
- **The pistol's left hand crosses the right while the clip fades** (above). A pose to join in which the hands do not
  overlap, or a game that blends the left hand off the pistol before the blow, would let the limit hold on every
  frame.
- **One clip plays on both mannequins.** It was keyed on the female; the male's longer arms reach 0.04 to 0.05 m
  further and bend the same.
- **No rifle clips**: the rifle has its own issue.
