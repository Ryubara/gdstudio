# Weapon pickups and the rifle

<!-- new section: shooting.md reached 53 KB when gdstudio #1040 (the rifle pickup and its two-handed hold) met main's
     aim layer; the pickup and the rifle's hold are one subject, apart from aiming and firing -->

Weapons found on the map and the rifle held in both hands: the floating pickup, giving a weapon at run time, and the
two-handed hold with its reload. Part of [the 3D Third Person template](../third-person-template.md); aiming, firing,
ammunition and switching are on [Crouch, aim and shoot](shooting.md).

## Weapon pickups and a two-handed hold {#weapon-pickups}

<!-- new section: the weapons section covers a loadout fixed in the scene; nothing said how a game hands a character a
     new weapon, or how a long gun is held when the animation library has no clip for it (gdstudio #889) -->

A weapon lying in the level is a `WeaponPickup` (`gameplay/pickup/weapon_pickup.gd` + `weapon_pickup.tscn`, a
`Pickup` that gives a weapon): its `weapon` (a `WeaponDef`) and `rounds`, the spin, bob, sound and `respawn_time` of
`Pickup`, and the nodes `Visual` (the model goes under it), `Shape` (a 1.2 m wide cylinder), `Glow` (an unshaded
additive ring on the ground in `tint`), `Light` (a 2.2 m omni light in `tint`, no shadow) and `Sound`. A weapon's own
pickup is a scene that inherits it and puts the model under `Visual`: the template's `rifle_pickup.tscn` (the rifle,
60 rounds, 20 s) stands in the prototype map between the spawn and the range.

- **What it gives** goes through the character's loadout, `WeaponLoadout.give(definition, rounds)`: a weapon not
  carried goes in a new slot with a full magazine and `rounds` in the reserve and is brought out
  (`switch_to_new`, on), one already carried takes only the rounds up to `max_reserve` (`Given.AMMO`), and one with
  a full reserve takes nothing (`Given.NOTHING`), so the pickup stays. A body with no `WeaponLoadout` leaves it. The
  pickup says `weapon_taken(collector, definition, given)` and `collected`. Any `Pickup` can give something else by
  overriding `_give(body) -> bool` and `_set_shown(shown)`; `Visual` can be any `Node3D` and bobs about its height in
  the scene.
- **Gameplay and cosmetics.** The carried list is in the loadout's step state (`CharacterState.loadout[6]`), so a
  server and a predicting client agree on what a pickup gave, and a restore takes a given weapon back. The spin, the
  glow, the light and the sound are cosmetic. Adding to `slots` at run time is additive: a screen that lists the
  weapons (an inventory) reads `slots` and redraws on `slots_changed` (a weapon given, or taken back by a restore).
- **The two-handed hold** is `TwoHandHold` (`gameplay/weapon/two_hand_hold.gd` + `two_hand_hold.tscn`; the rifle's
  `rifle_held.tscn` inherits it and adds the gun, the hands' places and the finger poses), the definition's `view`. It
  is not in the character's scene: the loadout makes the definition's `view_scene` under the `Model` slot the first time
  the character carries the weapon, so a character without a rifle carries none of its nodes. Its parts are below:
  [the rifle in both hands](#rifle-hands).
- **The rifle**: hitscan, automatic, 10 shots a second, no spread on a first shot growing to 1.2 degrees over 5
  shots in a row and back in 0.35 s ([spread](fire-modes.md#spread)), recoil 0.6, damage 22, a magazine of 30,
  60 to 180 in reserve (`rifle_ammo`), reload 2.2 s, holster 0.3 s, draw 0.4 s; Deadnight's synthesised M4A1 sounds
  (`assets/audio/rifle/`, MIT), the shot at -27 dB.

Tests: `test_weapon_pickup.gd` (walking into it gives the rifle and its rounds, it comes back after its time, with the
rifle carried it gives only rounds, with a full reserve it stays, the rifle fires while the button is held, a body with
no loadout leaves it, both hands reach their places and let go when it is put away, the step state takes a given
weapon back), `test_rifle_hold.gd` ([the rifle in both hands](#rifle-hands)) and `test_rifle_run_state.gd` (the run,
the sprint and the slide with the rifle are the same fresh, after a switch, after a burst, after a reload and after
going unarmed, and the pistol's run the same after the rifle, on both bodies; `tools/capture/rifle_run_tour.tscn`
films it from the game camera with a side view, and with `RUN_STAGES=directions` the sprint in every direction and a
reload on it), `test_rifle_sprint_carry.gd` ([the sprint](#rifle-hands)) and `test_rifle_draw_trunk.gd` (no spine bone
past `chest_turn` and the head within 15 degrees of the front through a pickup and a switch to the rifle, standing, out
of a run and a sprint, on both bodies, kit #1327). Captures:
`tools/capture/rifle_tour.tscn` from the game camera (the floating rifle, taking it, the low ready, a walk, the aim, a
burst, the aim up and down, the reload, hip fire, a crouch, a switch to the pistol and back) and
`tools/capture/rifle_hands.tscn` (six close-ups at once in every state).

Cost, measured on the desktop: a pickup's spin and bob 0.8 to 0.9 microseconds a frame; ten rifle pickups drew 35 draw
calls on the Compatibility renderer and 14 on Forward+, the same with their lights as without (each rifle is its near
level's three meshes and the ring). The hold's cost is with [its section](#rifle-hands).

- **Approach:** In a test that walks a character through a pickup with a respawn time, make the respawn longer than
  the whole walk in and out, then wait for it. **Watch out for:** with a 0.5 s respawn the rifle pickup came back
  while the character was still walking out over it and gave its rounds twice (180 in reserve, not 120). **Seen:**
  gdstudio #889, 2026-11-10.
- **Approach:** When a part moves from the scene to being made on demand (the held rifle under `Model`, made by the
  loadout when it is first carried), grep `tools/` for every `get_node` of it too and run each capture scene once: the
  export leaves `tools/` out and no suite loads it. Look such a node up when it is needed (`get_node_or_null`), never in
  `_ready`. **Watch out for:** `rifle_tour.gd` took `RifleHeld` in `_ready`, so after the change every frame of the tour
  printed a `SCRIPT ERROR` and nothing measured the hold, found only when the tour was run for the next round.
  **Seen:** gdstudio #889, 2026-11-10 (fix: `_rifle_out()` looks it up when the rifle is out).

### The rifle in both hands {#rifle-hands}

<!-- new section: the weapons page's hand rules are written for a weapon that rides a hand bone in a clip; a long gun
     with no clip is placed in the model's space with both arms reaching it, and its switch and reload are built in
     code (gdstudio #889, after the maintainer's review of 2026-11-11) -->

How a carbine is held, which the hold copies. The firing hand is high on the pistol grip, with no space left under
the receiver, and the support hand is forward on the hand guard with its thumb along the rail's side, pulling the
rifle back into the shoulder ([Guns & Ammo](https://www.gunsandammo.com/editorial/tactical-shooting-get-ahold-of-that-carbine/248479)).
The trigger finger is taught straight along the lower receiver until the shot
([Soldier Systems](https://soldiersystems.net/2023/07/15/blast-from-the-past-follow-through-consulting-weapon-grip-for-rapid-movement/)).
At the low ready the butt stays in the shoulder's pocket and only the muzzle goes down, about 45 degrees
([The Armory Life](https://www.thearmorylife.com/ready-up-three-ar-rifle-presentation-techniques/),
[Safariland](https://inside.safariland.com/?p=31063)). In a reload the support hand fetches the new magazine from its
pouch and seats it ([Pew Pew Tactical](https://www.pewpewtactical.com/how-to-reload-ar-15/)). Ours beyond those
pages: three fingers round the grip's front with the thumb round its far side, the support palm under the hand
guard with four fingers up its right side and the thumb up its left, the firing hand on the grip through the reload
and the old magazine taken out by hand (the model's magazine is one node, so it leaves and comes back).

Since kit #1187 the template's characters wear the prototype bodies, whose hands are a person's size (0.18 m and
0.195 m from wrist to fingertip, against the Quaternius mannequins' 0.23 m), and the hold is solved on each body by
itself: the female's places and poses are the scene's own (`rifle_held.tscn`, `rifle_*_pose.tres`) and the male's are
a `HoldFit` (`gameplay/weapon/hold/rifle_fit_male.tres`) that `TwoHandHold.fits` lists and puts on when the model is
his file, as the pistol's `WeaponHold.fits` does (`HoldFit.chosen()`; a rifle fit's `seat` is the inverse of
`RightHandTarget`). The numbers below are the prototype bodies'; those of the Quaternius pair, which one hold fitted,
are named as such.

- **The stance.** The butt sits in the right shoulder's pocket, a place from `spine_03` in the chest's frame (turned
  with the chest about the up axis, and by `pocket_lean`, half, of its lean: `low_pocket`, `low_pitch` 35, `low_yaw`
  10 at rest; `aim_pocket` along `view_pitch` when the character aims or for `shot_hold_time` after a shot;
  `raise_time` 0.15 s, `pitch_limit` 60), so a crouch carries the gun. The pockets are given a little inside the
  chest: the gun then goes forward along its barrel until no point of the torso's skin is inside the butt
  (`butt_pad` 6.2 by 14.5 cm, `butt_depth` 16 cm along the stock, `butt_margin` 1 cm), the skin being points over the
  body's own torso triangles on the rest pose, one a `skin_spacing` (3 cm) cell and each ridden by its nearest
  corner's main bone, so the butt comes to the skin of whichever body holds it (kit #1177). While the muzzle is down
  the butt comes out of the pocket level, not along the barrel (`push_level`, 1; kit #1346): along a barrel 45
  degrees down the move slides the butt down the chest, so it was 143 mm (female) and 161 mm (male) from the pocket
  before the stock's toe was clear, against 63 and 72 aimed level, and sat on the breast, not the shoulder; out
  level it is 89 and 107 mm, the stock still clear of the torso. Aimed up the barrel's way stays (the push is 3 to
  41 mm there). The push is the least move no skin point forbids, so skin ahead of the stock that the move brings
  back along it counts too. The chest stands turned
  `chest_turn` (-30 degrees) from the model's front: `two_hand_stance.gd` takes the clip's own turn of the chest off
  first, so a walk or a run that swings the shoulders keeps the left shoulder forward, and turns the head back by what
  it turned the chest, so the head keeps the facing the locomotion clip gives it (kit #1333); while the gun is up a
  chest leaning more than `aim_lean_limit` (25 degrees, a crouch's hunch) is raised toward it, so the head is over the
  stock and not in it. When the hand guard is still farther from the left shoulder than `arm_stretch` (0.97) of the arm,
  the left collarbone turns toward it (`reach_turn`, up to 55 degrees: the shoulder comes forward to the fore-end), with
  the gun where the last frame's push had it; the butt is brought to the skin after it, since the turn brings the
  chest's left side forward under the stock, and both again in the same frame only when the push moved more than 3 mm.
  What is still short then brings the gun back along its barrel (`pull_limit`, 0 now: nothing is short).
- **The left shoulder.** On a left peek lean the stance mirrors the pocket and the gun's turn across the body and
  turns the chest nearly square on (`side`, `left_chest_turn`); the hands keep their places on the rifle
  ([the weapon on the left side](peek.md#left-shoulder), gdstudio #1435;
  [the arms out of the chest on either lean](peek.md#rifle-lean-arms), #1436).
- **The arms** are a `HoldArm` each (the pistol's own reach, given the hand's place in the skeleton's space by the
  stance in the same update), toward `RightHandTarget` and `LeftHandTarget` on the rifle, the elbows toward
  `RightPole` and `LeftPole`. Both are on their places in every update of every state (0.0 mm in 110 poses of both
  mannequins; the engine's `TwoBoneIK3D` aimed at a node is a frame late,
  [the pistol's hold](../../../tools/blender/weapons.md#the-third-person-template-pistol)).
- **The fingers** are a `HandPoseModifier` per hand: `rifle_grip_pose` (three fingers round the grip, the thumb round
  its left side, the index finger straight along the right side over the trigger guard), `rifle_trigger_pose` blended
  over it as the gun comes up (`raised_amount()`: the finger is on the trigger only while aiming or firing, and off it
  through a reload), `rifle_support_pose` (the palm under the hand guard, four fingers up its right side, the thumb up
  its left), `rifle_open_pose` and `rifle_magazine_pose` for the reload. The places and the poses are written by
  `tools/hold/solve_rifle_hold.py --body=<body>` from the rifle's own triangles and that body's skin
  (`dump_hold_rig.gd`, which also writes each body's shoulders and elbows in the rifle's space, then
  `write_hold.gd -- <file> rifle <body>`), so no number of them is typed. The whole solve of a body takes 20 s.
- **Where the grip hand sits** is the solver's `MOVES` for the body, found by looking and then measured: the web
  under the receiver's tail behind the grip, the back of the hand over the grip's right panel, the knuckles across
  the grip at a slant of 30 degrees (the index knuckle highest), the heel of the palm 10 degrees out to the right,
  where the forearm comes from. The slant is what a hand does on a raked grip: the straight index finger then points
  up at the receiver's side and lies on it, 55 mm (female) and 59 mm (male) from `Trigger`, and the wrist bends 7 to
  12 degrees. The thumb's last two bones stay under the receiver (`THUMB_TOP`), on the grip's left panel, and the
  support thumb's tip ends on the hand guard's left side between 5 mm under and 20 mm over its middle
  (`SUPPORT_THUMB_UNDER`, `SUPPORT_THUMB_OVER`, `SUPPORT_THUMB_Z`).
- **The trigger finger's way** (kit #1036, kit #1283). The straight way from along the receiver to the trigger (a
  slerp of the two poses) takes the fingertip 19.9 mm (female) and 24.5 mm (male) into the magazine well and the
  trigger guard: the straight finger lies along the well's side ahead of the guard and curls in before it is over the
  guard's opening. `trigger_way` (a `HandPoseWay`, `HandPoseModifier.second_way`) is the poses the finger passes
  through instead, spread evenly over the raise, seven on each body: the knuckle lifts the finger off the receiver's
  side and turns it down and about its length (30 to 35 degrees, no more: a finger has only a little of that turn),
  the finger curls beside the rifle clear of the guard, then the knuckle brings the curled finger in through the
  guard's side onto the trigger. It is planned by `tools/hold/plan_trigger_way.py` on what
  `tools/hold/solve_trigger_way.gd -- <body> --dump=<file>` writes (that body's skinned finger as `HandContact`
  counts it, with that body's hold on, and the rifle's triangles): every pose of a grid of the knuckle's spread,
  bend and roll and the two joints' bends (4 million) is measured against the rifle's distance grid, a fine grid
  round each end leaves it (each end sits wedged on two faces), the shortest walk through the poses off the surface
  joins them, and it is cut to the fewest poses whose legs stay within 1.6 mm (two minutes a body).
  `solve_trigger_way.gd -- <body> --way=<file>` checks every leg at 40 steps with the game's own measure and writes
  the female's into `rifle_trigger_way.tres` and the male's into his fit (`HoldFit.trigger_way`), nothing when a
  step is deeper than 2 mm; run it after `write_hold.gd`, which keeps a fit's way. Measured at every hundredth of
  the raise (`test_rifle_fingers.gd`): at most 1.59 mm in (female) and 1.60 mm (male), against 3.7 and 4.6 mm for
  the way of two poses before (a roll of 90 and 105 degrees). The ends hold as before. The planner knows nothing of the
  rifle: the pistol's trigger finger is planned by it too, its dump adding the grid, the limit, the left hand's skin
  and depth read through thin parts ([between the poses](../../../tools/blender/weapon-hands/two-handed-pistol-grip.md#between-the-poses));
  what both solvers share is `tools/hold/finger_way_files.gd`.
- **A switch** is one sequence on the loadout's own times. Going away, the gun goes down to its stow place
  (`stow_pocket`, `stow_pitch`, `stow_yaw`) with both hands on it through the `holster_time`, is hidden in the tick
  the next weapon appears in the right hand, and the arms go from the gun's places to that weapon's pose while it
  comes up (`reach_amount()` falls with `WeaponLoadout.lowered_amount()`). Coming out, the arms go to the stow place
  while the weapon before it goes down, the gun appears in the hands there and comes up through its `draw_time`.
- **The reload** takes only the left hand, by `Weapon.reload_progress()`: its knuckles open first and the rest of
  each finger after them while the hand drops 6 mm (`HandPoseModifier.open_first`), then it goes down and out to the
  thumb's side off the hand guard (`reload_clearance`), across to beside the magazine and onto `MagazineHand`
  (`reload_leave`), closes on the magazine, takes it straight down out of the well (`magazine_well`) and to the belt
  at the left hip (`reload_belt`, a place on the body; `reload_out`), where the magazine is out of sight and changed,
  comes back up and straight in (`reload_in`), pulls the charging handle after an empty magazine (below), and goes
  back under the hand guard the way it came (`reload_return`).
  The `magazine` node rides the hand. The thumb goes from the hand guard's side to its place behind the magazine
  while the hand comes down off the hand guard (`_WAY_THUMB`), and on the magazine the four fingers close as one
  (`HandPoseModifier.open_together`; off the hand guard they open knuckles first).
- **An interact** takes the left hand too, for the interact clip's reach: off the hand guard the reload's way, out
  to `free_clearance`, and to the clip's arm, while the right hand takes the gun down (`free_pitch`, `free_yaw`) and
  the chest's turn eases off ([Using something with a weapon in the hands](interact.md#interact-held)). The torso's
  skin the butt meets is a class of its own since then (`gameplay/weapon/hold/torso_skin.gd`, `TorsoSkin`), moved out
  of `two_hand_hold.gd` at the 1000 lines a script may have.
- **A melee blow** keeps both hands on the rifle: its clip carries the rifle on the right hand while it plays and the
  hold's chest turn and shoulder reach ease off by the clip's share (`HoldBlow`,
  [melee](melee.md#melee)).

The body under the hold is the rifle's own clips (kit #1082, the library `rifle`): `rifle.tres` names
`Rifle_Idle` as the grip clip on `spine_01` and all under it, the three aims, `Rifle_Shoot` added on top of the aim
(`WeaponDef.shoot_additive`) and `Rifle_Reload`. The hold runs after them and still puts the rifle and the hands;
the clips were built round it on both bodies, each under its own fit
([clips under a hold](../../../tools/blender/clips-under-a-hold.md#body-under-the-hold)), so when the hold's
numbers, a fit or the solved hands change, their build is run again
(`assets/animation/rifle/build_rifle_clips.py`, 90 s; a new step of the hold is ported to the build's `Hold`
first). The
left arm's way to the charging handle and its pull are the hold's `ChargePull`, ported to the build's `Hold`
(kit #1266).

- **The charging handle**: after the new magazine of an empty reload the left hand pulls it (kit #1266, kit
  #1402, `ChargePull`), on
  [its own page](rifle-charge.md#rifle-charge).

Measured on the skinned mesh against the rifle (`HandContact`, the same in every clip, since the fingers are absolute
and the arms reach their places), on the prototype bodies:

| Hand | Deepest in | Holding part farthest off | Index tip to `Trigger`, low and aimed |
| --- | --- | --- | --- |
| Female, right | 1.2 mm (the middle finger) | none off: each is pressed 0.2 to 0.9 mm in | 54.7 mm, 5.4 mm |
| Male, right | 1.2 mm (the tip on the trigger) | none off: 0.5 to 0.8 mm in | 58.9 mm, 6.5 mm |
| Female, left | 1.2 mm | none off: 0.7 to 0.9 mm in | |
| Male, left | 0.9 mm | none off: 0.6 to 0.8 mm in | |

The web of the thumb is 12.8 mm (female) and 7.2 mm (male) off the grip's back; it is not a holding part. On the
Quaternius pair one hold fitted both: at most 1.4 mm in, the female's palm 4.4 mm off. Before the rework the clip's
fist stood 22 mm inside the grip with its fingers 8 to 17 mm in and the index finger off the trigger, the left hand
14 to 45 mm inside the hand guard, and the left arm 5 to 98 mm short of its place in the walk, jog and sprint clips.
On the way between its places in the reload the left hand passes at most 2.9 mm (female) and 2.3 mm (male) through
the rifle, measured every half hundredth, which is the test's step too (it caps it at 6 mm, as the pistol's).

Tests, `tests/gameplay/test_rifle_hold.gd` with `tests/fixtures/rifle_stage.gd` (a mannequin and the hold posed by
hand): both hands within the 2 mm and 5 mm in six locomotion clips at the low ready and aimed, and with the view 30
and 45 degrees up and down, on both bodies, the right palm and thumb among the holding parts; in the same poses no
point of the rifle more than 10 mm in the torso (`test_the_stock_stays_out_of_the_chest`); every 15 degrees from 45 down
to 45 up, standing and crouched, the butt within 20 mm of the torso's skin and no more than 50 mm farther from the
pocket than at the level aim (`test_the_butt_stays_on_the_shoulder_through_the_pitch_range`; along the barrel it was
56 to 89 mm farther); the index finger within
12 mm of `Trigger` only while the rifle is up and more than 20 mm from it otherwise; the reload every half
hundredth; and on
the live player with simulated input, every update of idle, walk, sprint, aim, fire, crouch and crouched walk, the
reload by its key, and a switch to the pistol and back (never two weapons, never none, the rifle never shown without
both hands on it, the arms on its places before it shows and leaving after it hides). `test_hold_fit.gd` has the
male's fit put on and taken off with the model (his trigger finger's way with it), and `test_hand_pose_modifier.gd`
the order the fingers open in. `tests/gameplay/test_rifle_fingers.gd` (kit #1036) measures every finger of both hands
on the live player (its animation tree and the hold as they run, simulated keys and mouse, both bodies) in standing,
walking, sprinting, aiming, firing, crouched, crouched aiming and crouched walking, and the trigger finger's way
at every hundredth of the raise on each body, within the hold's 2 mm (`RIFLE_WAY_SWEEP=<file>` writes each step's
depth). `tools/capture/rifle_trigger_way.tscn` films the finger going onto the trigger close up on both bodies.
`tools/capture/rifle_fingers_view.tscn` films six views from the game camera's eye swung round the character
(`RIFLE_FINGERS_BODY=male` for the other body).

Cost, headless on the desktop (`tools/bench/hold_cost.tscn -- rifle`, 40 mannequins, the least of five runs each on
a machine other agents were loading): the rifle's hold 77 microseconds a character a frame against 35 for the
pistol's aimed hold in the same session, so about 2.2 times it (the pistol's figure on a quiet machine is 12.6). It
is five modifiers and the hold's own `_process`; it is worked out on each machine from `aim_amount`, `view_pitch`,
the shots, the reload and the loadout's switch, never sent.

In Chrome (kit #1178, `gds template bench-web 3d-third-person hold_cost --run`, then `hold_cost.py <build> 1 "" male`
for the male body; 40 of the template's own bodies, a camera on every run, two rounds of main and the branch in
turns, microseconds a character a frame, female / male): before the cut the rifle at the ready 49 / 52, low 46 / 50,
reloading 51 / 52, past `fingers_far_distance` 50 / 49, the pistol aimed 26 / 23 and carried 16 / 12; after it 31 /
34, 29 / 34, 37 / 39, 27 / 27, 14 / 15 and 8 / 8. The bench's frame for the rifle went from 2.7 to 2.0 ms on both
bodies (far: 2.6 to 1.6), the frame with no hold unchanged (0.7 ms). At 4x the male's rifle went from 24.5 to 18.5 ms;
the female's single round there was within the noise (18.7 and 20.4). The cut finds the hold's nodes and bones once,
works the chest and shoulder out from the local poses, writes the pivot once a frame, puts the left hand and the
magazine back only when a reload ends, keeps its weapon definition until the slots change, lays the hand poses out
into arrays, and past `fingers_far_distance` (set by `CharacterAnimationThrottle`, which already measures the
distance; the hold reads no camera) leaves the fingers on the clip's fist. Every bone came out the same on both
bodies in twelve poses (aimed, low, the reload at four shares), the pivot and the magazine within 2e-7 m.

Bringing the butt to the skin (kit #1177) adds to that, same bench, one round a body in Chrome against the hold
before it in the same session (microseconds a character a frame, female / male): the rifle at the ready 60 / 62
against 39 / 38, low 55 / 63 against 32 / 37, reloading 66 / 71 against 46 / 50, past `fingers_far_distance` 37 / 52
against 32 / 29 (the male's far figure was 40 in an earlier round); the bench's frame for the rifle 3.1 / 3.2 ms
against 2.3 / 2.2. It was 86 / 83 at the ready as first ported (two passes over every skin point, each bone's pose
asked of the engine, the reach found by halving). What cut it: the skin's 191 (female) or 194 (male) points lie in
groups of an 8 cm cell under each bone with a box round each group and each bone, so a frame tests about 18 points;
the shoulder reaches for the gun where the last frame's push had it and the push is measured once after it, again
only when it moved more than 3 mm (a new pose); the reach's angle is worked out in closed form; every pose comes
from the local ones; past `fingers_far_distance` the last near push is kept.

Cut again (kit #1347), the same bench, the branch and `main` in turns, two rounds a body (microseconds a character a
frame, female / male): the rifle at the ready 39 / 36 against 54 / 54, low 39 / 36 against 51 / 55, reloading 46 / 42
against 62 / 57, past `fingers_far_distance` 25 / 22 against 33 / 33; the pistol carried and aimed as they were (10 /
10 and 19 / 16 against 9 / 9 and 19 / 18). A build from before the stock fix (after kit #1289), in the same session,
read 31 / 32, 29 / 27 and 38 / 36, so the push and the shoulder's reach still cost 6 to 9 more than the hold did
before them. Every bone came out within 2.3 micrometres of `main` in 36 poses (both bodies, six clips, up and down,
four shares of a reload). What cut it, in order of what it saved: the small helpers written out at their callers
(the web build pays more for a GDScript call than for a line, [what a line costs](../gdscript.md#web-cost)), the push
turning each group's points by one engine call (`Transform3D * PackedVector3Array`, `AABB.has_point`) and meeting the
groups' boxes in the bone's space, the stance handing `place()` the spine's top pose (`HoldBones`), what is written to
the modifiers kept and written only when it changes (`HoldWeights`), the trigger finger set straight to its pose when
it is all the way on, and no pull worked out while `pull_limit` is 0. With the butt's push along `push_level`'s way
(kit #1346) merged in, the push along it (`TorsoSkin._push_along()`) takes the same three speedups; the low ready aims
the barrel down and takes that way, so most of its cost is the new push: on a busy machine 72 / 119 against 79 / 119,
where the ready went 50 / 74 against 70 / 93 and the reload 54 / 82 against 75 / 103.

Cut again (kit #1433), the same bench, the branch and `main` in turns, three rounds a body: the low ready 60 / 60
against 68 / 84, the ready 49 / 47 against 48 / 48; every bone the same as `main` in 100 poses. The low ready went
through 143 / 170 skin points a frame against 37 / 54 at the ready: the groups' boxes were met against the stock's
sweep turned into each bone's space, and that long, thin box turned there covered most of the torso. Now each point
is turned into the frame of its own run (the move that brings the stock's back edge to it, and the one that brings
its edge across), where the sweep is a box and the run two sums; and the sweep is first looked at only as far as the
last push and 2 cm, exact for any push under that (a point the stock does not pass over forbids no shorter move), the
whole reach again only when the push reaches it. It goes through 34 / 61 points; the low ready is still 11 / 13 over
the ready, the 23 / 32 points that do forbid a move.

Cut again (kit #1347, second round), the same bench, `main` and the branch in turns with a build from before the stock
fix, three rounds a body (female / male): the ready 40 / 45 against 48 / 47, the low ready 50 / 56 against 54 / 61,
reloading 53 / 49 against 51 / 56 (the female reload within the noise); before the stock fix 35 / 36, 34 / 33 and 48 /
47. The push takes the spine's poses from the stance (`TorsoSkin.use_spine()`: the stance's own array, read once, so a
push no longer works five bones out from the root; 1.3 microseconds a push), meets the groups' boxes in the gun's space
(18 / 27 points gone through at the ready, against 37 / 54), and gives each point's run in one line (an empty run and
one that ends at or before 0 change nothing). Every bone within 0.84 micrometres of `main` in 124 poses. What is left
over the hold before the stock fix is the push and the reach themselves (about 5 microseconds at the ready on the
desktop, 9 to 13 for the push along a way at the low ready, which kit #1346 added): the bone and group boxes, the
points the stock passes over and the runs' sort are each 1 to 2.5.

The stock in the body (`tests/fixtures/body_clearance.gd`, `BodyClearance`: every point of the rifle against the
body's skinned mesh at its nearest level, inside by a ray's crossings, the torso only, the arms, legs and head left
out), the deepest in the six locomotion clips at the low ready and aimed and aimed 30 degrees up and down, on the
prototype bodies:

| | Before (kit #1040) | After |
| --- | --- | --- |
| Female | 79.1 mm; 24 to 47 standing | 0.0 mm, the butt 14 mm off the skin at the median, 20 at most |
| Male | 93.4 mm; 49 to 70 standing | 0.0 mm, 11 mm off at the median, 18 at most |
| Either hand short of its place | 0 mm (the butt in the chest bought it) | 0 mm |

Three things were needed together. The stock is collapsed 5 cm on the model (`build_rifle.py`'s `STOCK_IN`, an M4's
stock on its first positions; the butt 0.257 m behind the grip): with the full stock and the butt on the skin the
left arm was 4 to 10 cm short. The pocket is lateral, at the deltoid's edge (`x` -0.16 from the spine): at -0.10 the
stock lay across the sternum and the left collarbone's skin came forward into it as that shoulder reached. The low
ready points 10 degrees across the body, not 20: with the chest turned, a gun yawed further lies along the chest
and no push along its barrel clears it. From the game camera the rifle covers no less of the screen than before
(`tools/capture/rifle_tour.tscn -- pixels`, of 2.07 million: 108 pixels at the low ready against 60, 3,276 aimed
against 2,420, 4,964 crouched and aimed against 3,412; behind the body at rest, as
[a held weapon from the shoulder camera](../measuring-effects-on-screen.md#a-held-weapon-from-the-shoulder-camera)
expects). The hands' places on the rifle and the finger poses are as solved (the stock alone changed on the
model). Captures: `tools/capture/rifle_stock.tscn` (both bodies from the right and the front, `-- stand` or
`-- move`).

**The sprint** (kit #1340) is measured over the whole body, not the torso alone: `BodyClearance.new(..., HOLDING)`
leaves out only the forearms and hands, so the thighs, upper arms and head count. On the live player with simulated
keys, three strides of our own sprint (#1275, with #1158's speed matching), fresh, after a burst and after a switch to
the pistol and back, and one stride each running back, left, right and on two diagonals, on both bodies: 0.0 mm in, both
hands 0.0 mm off their places (`test_rifle_sprint_carry.gd`: the hands on every update, the skin on every fifth, 22
phases of the 36-update stride; on every update the probes read the same). The rifle's nearest point to the skin is 5 to
17 mm off on the female and 1.2 to 9 mm on the male. Probes found the same at 15 frames a second, turning with the
mouse, starting from standing and with a reload on the sprint (both bodies), and with the library's `ual1/Sprint` in
place of ours (the female). The run and the stop after a sprint graze the chest by 2 to 3 mm (`spine_02`), under the
stock test's 10 mm.

- **Approach:** Measure a held weapon against the body it is held by (a parity test on the closed skinned mesh, the
  arms and legs left out), in every clip, before trusting a stance, and bring the body's contact about at run time
  from the model's own skin when two models share one stance. **Watch out for:** the first stance placed the butt by
  offsets from `spine_03` in the model's space, chosen so the short arm reached; the butt then sat 2 to 9 cm inside
  the chest, hidden from the game camera, and fixed offsets tuned on one body left the other 4 to 7 cm off its chest.
  **Seen:** gdstudio #1177, 2026-11-11 (fix: the butt pushed to the skin, the stock collapsed, the collarbone's
  reach; 0 mm in).
- **Approach:** Fire a layer's one-shot only when the held definition names a clip for it (`ShotLayer.fire()`), and
  prove every gait against itself after each thing that can come before it (a switch, a burst, a reload, unarmed),
  on the layers' weights and the body, over whole strides (`test_rifle_run_state.gd`). **Watch out for:** a weapon
  with no shot clip (the rifle until #1267 gave it `Rifle_Shoot`) has the idle clip as its layer's stand-in, and
  every shot played that idle over the upper body for 6.25 s: the run stood 13 degrees more upright after a shot and
  a sprint or a slide kept the idle's chest; a mean over part of a stride moved the hand 30 mm between two readings.
  **Seen:** gdstudio #1333, 2026-11-12 (fix: no shot clip, no one-shot; readings equal to 0.1 degrees and 1 mm).
- **Approach:** Before fixing a fault seen in a playtest recording, measure it on main and on the commit the recording
  was made on, with the measure the fault names (the thigh, not the torso), in every situation the frames show
  (direction, after a shot, a reload, the frame rate), and read the frames for what they prove: a barrel drawn over a
  thigh from behind is in front of it, not through it. **Watch out for:** the rifle in the sprint read as dangling and
  through the thigh in a playtest on main at #1291; on main after #1349 and #1275 it measured 0.0 mm in every
  direction on both bodies, and in the arena even the recording's commit measured clear on the female, so there was
  nothing left for a carry pose to fix; the existing stock test could not have said so, since it leaves the legs out.
  **Seen:** gdstudio #1340, 2026-11-12 (kept: `test_rifle_sprint_carry.gd` over the whole body).
- **Approach:** In a suite, call `BodyClearance.deepest()` without `with_gap` and on a sample of updates whose step
  shares no factor with the stride; keep the gap for probes. **Watch out for:** with the gap on every update the
  sprint suite took 592 s in the full template run (a nearest-triangle search for every point of the rifle), against
  11 s without it on every fifth update. **Seen:** gdstudio #1340, 2026-11-12.
- **Approach:** When a modifier takes a clip's turn off one bone (the chest's swing in a run), give the turn back
  above it on a bone whose skin is clear of the weapon (the head), measure the head's turn through a whole stride
  against empty hands, and run the hold's own suite after any change to a bone near it. **Watch out for:** a run
  counters the shoulders' swing in the neck, so with the chest held at `chest_turn` the head swung 109 degrees at
  every stride; turning `neck_01` back put its collar skin 12 to 24 mm into the stock in the crouch. Since #1267 the
  rifle's own idle holds the upper body, so little swing is left (head 1.8 degrees, 1.0 with the turn back).
  **Seen:** gdstudio #1333, 2026-11-12 (fix: `two_hand_stance.gd` turns `Head` back; `test_rifle_hold.gd` green);
  gdstudio #1327, 2026-11-12 (the same missing turn back was the head's 77 degrees in the rifle's draw).
- **Approach:** Before fixing a pose fault seen in a capture, probe it frame by frame on today's main and on the
  commit it was seen on (`gds template game` in a detached worktree), each spine bone's turn from the front after
  every modifier, and name what cured which part. **Watch out for:** the stance takes the gap to `chest_turn` off in
  even thirds over `spine_01` to `spine_03`: under the library run's stop the clip's chest stood 47 degrees left, so
  `spine_02` stood 42 right and the head, riding the chest, 77 (the draw's three frames). Kit #1333 cured the head,
  our run loops (#1275, 7 degrees of swing) the spine; a wider clip brings it back (gdstudio #1379).
  `test_rifle_draw_trunk.gd` holds it: 30.0 and 7.2 at most on main, 43.6 and 80.9 on the old commit. **Seen:**
  gdstudio #1327, 2026-11-12 (gone on main; the test keeps it gone).
- **Approach:** Sample a skin for a run-time contact over its triangles at the spacing you thin to, not at its
  vertices alone, take only the nearest level of detail (`CharacterBodies.near_meshes`), and measure again on every
  body the template wears when the bodies change. **Watch out for:** the push to the skin was built on the
  Quaternius skins, whose vertices are dense; on the prototype male, with few large triangles, a stock clear of
  every vertex stood 10 to 19 mm inside a face at the low ready, and no margin or pad size cured it. **Seen:**
  gdstudio #1291, 2026-11-12 (fix: points over each triangle; 0 mm on both bodies).
- **Approach:** Time the parts of a per-frame step inside the bench that runs the crowd (a counter round each
  part, printed every few thousand calls) before cutting any of them, and give a point test a box per group so
  most points are never visited. **Watch out for:** a probe that called the push 2,000 times on one idle figure
  read 5.6 microseconds and the bench 13; grouping the points alone moved nothing, since the loop over 45 groups
  cost what the points had, until a box per bone went over the groups. **Seen:** gdstudio #1291, 2026-11-12.

- **Approach:** Judge a hold from both sides of each hand, from above and from the game camera, in every state the
  weapon has, and test each thing a person would call wrong: a palm off the grip, a finger beside the trigger, a
  support hand under the gun and not round it, a hand that leaves the gun where the state does not ask for it, a frame
  of a switch with two weapons or with a weapon and no hands. **Watch out for:** the rifle's first hold put each
  hand's bone on its target and was reported as held, on captures from the right side only: the right hand was a fist
  beside the grip, the left lay palm-up under the hand guard and let go at idle, the fingers were put off to another
  issue, and in a switch the rifle hid after the arms had left it. **Seen:** gdstudio #1040, 2026-11-11 (the
  maintainer's review; fix: the solved places and poses, `reach_amount()` and the tests above).
- **Approach:** Count a fingertip's leaf bone with the finger's last bone wherever skin is sorted by bone, in the
  solver and the test alike, and check a solver's candidate points against the pose it then sets. **Watch out for:**
  the female mannequin's fingertips are weighted up to half to `index_04_leaf_r` and its like, the male's are not:
  `hold_hand.py` moved only the chain's three bones in a candidate, so half of each female fingertip stayed where the
  last pose had it (up to 28 mm off), and the solver and `HandContact` both left out the vertices a leaf carries most
  of (15 on an index finger). The trigger finger then measured 3.8 mm inside the trigger or 15.6 mm from it, read as
  a trigger guard too short for a finger; with the leaf counted it sits 9 mm from `Trigger`, 1.2 mm in. **Seen:**
  gdstudio #889, 2026-11-11 (fix: `Hand.tips`, `hold_rig.py`'s owner rule, `HandContact._owners()`).
- **Approach:** Open fingers that are hooked over a part at the knuckles first, with the hand backing off a little,
  then straighten them, and measure the way between two places at a finer step than the test's. **Watch out for:**
  every finger bone blended to the open pose at one rate swung the left hand's fingertips 22 mm through the hand
  guard for a hundredth of the reload, each joint opened alone was worse (30 mm), a hand moving aside under closed
  fingers pushed the far side's 12 mm in, and one dropping straight down dragged the thumb 11 mm through it.
  **Seen:** gdstudio #889, 2026-11-11 (fix: `open_first`, a 6 mm drop while the knuckles open, then down and aside
  together; 4.4 mm at most).
- **Approach:** Turn the chest to an absolute angle (take the clip's own chest turn off first) and pull the gun back
  along its barrel when the support arm would be over 0.97 of its length. **Watch out for:** a chest turn added on top
  of the clip left the left arm 5 to 98 mm short of the hand guard in the walk, jog and sprint clips, whose shoulders
  swing; idle and aim, which the first captures showed, were fine. **Seen:** gdstudio #889, 2026-11-11 (fix:
  `two_hand_stance.gd`, `arm_stretch`, `pull_limit`; 0.0 mm in 110 poses).
- **Approach:** Seat a palm by the skin the hand bone carries at least half of and the forearm less than 3 % of, and
  solve on both mannequins at once. **Watch out for:** the game's IK bends the wrist 40 to 50 degrees on the rifle's
  grip and the skin at the heel of the palm follows the forearm, so a palm seated by all of its skin stood 5 to 7 mm
  off the grip in the game; the two mannequins' palms differ by 5.8 mm on this grip (the female's is the hollower),
  which leaves one place of the bone 1.2 mm of play between 2 mm in and 5 mm off. **Seen:** gdstudio #889,
  2026-11-11 (the male's palm is pressed 1.4 mm in, the female's is 4.4 mm off).
- **Approach:** Build a solver's distance grid exact only in a band round the surface (`BandField`, 3 cm) with a
  coarse grid beyond it, when the weapon is long. **Watch out for:** the pistol's grid at 1.5 mm over the rifle's
  0.64 m asks a million samples for the nearest triangle at about 90 microseconds each: over 35 minutes against 24 s.
  **Seen:** gdstudio #889, 2026-11-11.
- **Approach:** Give `HandContact.set_weapon()` the weapon after it is shown, and run a new modifier script through
  `--check-only` before a probe or a stage awaits it. **Watch out for:** `set_weapon()` skips meshes that are not
  visible in the tree, so a rifle still hidden by the loadout measured as no weapon at all (every part 30 mm off); a
  parse error in a modifier's script leaves the skeleton with nothing that dirties it, `skeleton_updated` never comes
  and `HoldStage.settle()` waits for ever with no error after the first line. **Seen:** gdstudio #889, 2026-11-11;
  gdstudio #1177, 2026-11-11 (a loop variable named `_step` shadowed the hold's `_step()`, a warning treated as an
  error, and a probe sat ten minutes on its first pose).
- **Approach:** Find a hand's place on a grip for each hand size, and judge it by the web's distance from the
  grip's back and the wrist's bend beside the contact; from the weapon's far side the back of the hand should cover
  the grip. Slant the knuckles across a raked grip. **Watch out for:** the place found by eye for the Quaternius
  hand (0.23 m) put the prototype hands (0.18 and 0.195 m) 4 cm too far back: the palm stood behind the grip with
  only the fingers on it, the web 23 mm off, the wrist bent 68 degrees. The contact test passed all but the straight
  finger, since the palm's nearest skin and the fingers did touch; a fix of the finger alone would have shipped it.
  **Seen:** gdstudio #1040, 2026-11-11 (fix: `MOVES` a body; the wrist bends 7 to 12 degrees).
- **Approach:** Carry a rule the solver holds as a distance (a finger off the trigger, a thumb on one side of a
  part) over to a new hand size by measuring it there first, and give a thumb a height to stay under and a side to
  stay on wherever it could lie more than one way. **Watch out for:** the first solve on the prototype bodies kept
  the Quaternius hand's rules: the shorter straight finger lay 15 to 17 mm from the trigger (the test wants 20),
  the female's thumb hooked round the magazine's far side and went 12 mm through it as the hand left, a thumb free
  to lie anywhere on the grip's left stood up the receiver's side, and the support thumb lay flat under the hand
  guard on one body and hooked over its top on the other (8 mm through it on the way off). **Seen:** gdstudio
  #1040, 2026-11-11 (fix: `REGISTER_TRIGGER_CLEAR`, `THUMB_BACK_Z`, `THUMB_TOP`, the `SUPPORT_THUMB_*` bounds).
- **Approach:** Measure a blend between two hand poses at its in-between steps too, and when the straight blend goes
  through the weapon, give the bones a way of poses round it (`HandPoseModifier.second_way`), solved on each body's
  skinned hand. **Watch out for:** the rifle's grip and trigger poses each held within 2 mm and the tests sampled
  only aim 0 and 1; a live test caught the finger half-way after a burst, 12.6 mm inside (the straight blend is 17
  to 24 mm deep). Poses put in at the deepest step stall when the end pose sits in a pocket (the trigger in its
  guard): try whole first ways (a roll, a bend, a turn) first. A way belongs to the poses it joins: once the grip
  place moved and each body had its own hold, it was solved again on each. **Seen:** gdstudio #1036, 2026-11-11
  (fix: `trigger_way` a body, `test_rifle_fingers.gd` sweeping the raise in 50 steps).
- **Approach:** After merging main into a parked hold branch, run the whole template suite before the push, and pin
  each export the branch adds in the suites main gained meanwhile. **Watch out for:** `test_rifle_hold_pins.gd`
  landed with the rifle while this branch waited: the hold suites the branch touched passed, and only the full run
  showed `trigger_way` and `second_way` unpinned. **Seen:** gdstudio #1289, 2026-11-12.
- **Approach:** Film a hold from the game camera with the camera's own eye swung round the character at its own
  distance and height, and a long lens on each hand from both of its sides (`tools/capture/rifle_fingers_view.tscn`),
  and look at the views again whenever the hold's place changes. **Watch out for:** straight behind, where the game
  camera sits, the body hides both hands of a rifle held in front of the chest; and after the grip hand moved, the
  one grip view (swung 125 degrees left) showed only the thumb's side, with the trigger finger, which the capture
  was made for, behind the receiver. **Seen:** gdstudio #1036, 2026-11-11 and 2026-11-12 (fix: a view swung 90
  degrees right for the trigger finger and one 80 degrees left for the support thumb).
- **Approach:** Sweep a hold through the game's whole aim range on every body (every 15 degrees, 45 down to 45 up)
  and choose the way a contact moves a part out, not only how far: a way along the skin needs more travel and
  slides the part off its place. Film a section at the contact. **Watch out for:** pushed along the barrel, the butt
  slid down the chest at 45 degrees down while the tests, aimed 30, passed; the rifle's own stock sections put the
  male's stock 12 mm in, as a skin thinned to a point a 3 cm cell lets a tight shape between its points; a level way
  aimed up made the push jump on a walk (`test_aim_head.gd`, 0.71 degrees a frame). **Seen:** gdstudio #1346,
  2026-11-12 (fix: `push_level` while the muzzle is down; `rifle_stock.tscn -- pitch`).
- **Approach:** Make the test of a moving hand step as finely as the scan that found its faults (half a hundredth
  of the reload here), and give each finger the order that suits the part: knuckles first off a part the fingers
  are hooked over, all joints together onto a part they close round. **Watch out for:** at steps of 2 hundredths
  the test passed while the female's little finger swung 8.1 mm through the magazine's front between two steps
  (closing tips first, the order made for the hand guard), the male's thumb passed 5.4 mm, and a thumb still
  standing up while the hand crossed under the magazine well passed 17 mm. **Seen:** gdstudio #1040, 2026-11-11
  (fix: `open_together` on the magazine, `_WAY_THUMB`, `RELOAD_STEP` 0.005; 2.9 mm at most).
- **Approach:** Plan a finger's way round a part as a search over a grid of its poses (`tools/hold/plan_trigger_way.py`:
  every node measured, the shortest walk through the nodes off the surface, then cut to the fewest poses whose
  legs stay within the limit), leave each end by a finer grid of its own, and check the result with the game's own
  measure before it is written. **Watch out for:** a tree grown from each end (RRT) never left them in 40,000
  tries: an end sits wedged (the straight finger's tip and middle on two faces at once), so almost every step from it
  goes deeper, and steps down the depth's slope turn back and forth between the points that hold it. With the
  knuckle's roll held at 0 no walk passed under 5.5 mm; with up to 30 degrees one passes clear. **Seen:** gdstudio
  #1283, 2026-11-12.
- **Approach:** Make a solver's distance grid cover everywhere the searched poses reach (the corners of their grid
  and many poses inside it), clipped to the weapon's own bounds. **Watch out for:** a grid round the straight way
  alone read a point beyond it as the edge's distance plus the way there, so a way through the receiver above it
  read 1.6 mm on the grid and 6 mm in the game. **Seen:** gdstudio #1283, 2026-11-12.
- **Approach:** Make a stage that a suite will `settle()` with `RifleStage.make_rifle(holder, model)`, the measured
  default. **Watch out for:** `measured = false` connects nothing to `skeleton_updated`, so `settle()` waits forever
  and GdUnit stops the suite at 5 minutes. **Seen:** gdstudio #1433, 2026-11-13 (`test_torso_skin_push.gd`).
- **Approach:** Keep `Pivot` (and so the rifle and its hand places) out of physics interpolation
  (`physics_interpolation_mode` OFF in `two_hand_hold.tscn`), and prove the hands on the rifle where the engine draws
  them (`test_rifle_drawn_hands.gd`), not only in `skeleton_updated`. **Watch out for:** the hold places the pivot in
  the skeleton's update, every frame; interpolated, the rifle was drawn where the last ticks had it while the skin
  had this frame's bones, 145 mm off both hands at each landing (the land clip drops the chest fast), and every pose
  test passed ([physics interpolation](../physics-interpolation.md#using-it)). **Seen:** gdstudio #1464, 2026-11-13
  (found by the jump captures of #1369).
