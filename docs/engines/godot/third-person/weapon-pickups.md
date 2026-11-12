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
- **The rifle**: hitscan, automatic, 10 shots a second, spread 1.2 degrees, recoil 0.6, damage 22, a magazine of 30,
  60 to 180 in reserve (`rifle_ammo`), reload 2.2 s, holster 0.3 s, draw 0.4 s; Deadnight's synthesised M4A1 sounds
  (`assets/audio/rifle/`, MIT), the shot at -27 dB.

Tests: `test_weapon_pickup.gd` (walking into it gives the rifle and its rounds, it comes back after its time, with the
rifle carried it gives only rounds, with a full reserve it stays, the rifle fires while the button is held, a body with
no loadout leaves it, both hands reach their places and let go when it is put away, the step state takes a given
weapon back) and `test_rifle_hold.gd` ([the rifle in both hands](#rifle-hands)). Captures:
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

- **The stance.** The butt sits in the right shoulder's pocket, a place from `spine_03` in the clip (`low_pocket`,
  `low_pitch` 35, `low_yaw` 20 at rest; `aim_pocket` along `view_pitch` when the character aims or for
  `shot_hold_time` after a shot; `raise_time` 0.15 s, `pitch_limit` 60), so a crouch carries the gun. The chest stands
  turned `chest_turn` (-30 degrees) from the model's front: `two_hand_stance.gd` takes the clip's own turn of the chest
  off first, so a walk or a run that swings the shoulders keeps the left shoulder forward. When the hand guard is
  still farther from the left shoulder than `arm_stretch` (0.97) of the arm, the gun comes back along its barrel until
  the hand reaches (`pull_limit`).
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
- **The trigger finger's way** (kit #1036). The straight way from along the receiver to the trigger (a slerp of the
  two poses) takes the fingertip 19.9 mm (female) and 23.7 mm (male) into the magazine well and the trigger guard:
  the straight finger lies along the well's side ahead of the guard and curls in before it is over the guard's
  opening. `trigger_way` (a `HandPoseWay`, `HandPoseModifier.second_way`) is the poses the finger passes through
  instead, spread evenly over the raise: rolled about its own length so its bend lies along the rifle's side, bent
  there, then turned onto the trigger. `tools/hold/solve_trigger_way.gd -- <body>` writes it from that body's skinned
  finger against the rifle's triangles, with that body's own hold on: the female's into `rifle_trigger_way.tres`,
  the male's into his fit (`HoldFit.trigger_way`); run it after `write_hold.gd`, which keeps a fit's way. It is held
  to the depth a hand may pass through a weapon between two places (6 mm, the reload's), not the 2 mm of a hand that
  holds: its legs pass 2.4, 2.8 and 3.4 mm (female, the roll of 90 degrees) and 2.7, 2.7 and 4.6 mm (male, 105
  degrees) at 16 steps each. On the Quaternius hand and the first grip place the best way passed 5.6 mm. The ends
  hold as before.
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
  comes back up and straight in (`reload_in`), and goes back under the hand guard the way it came (`reload_return`).
  The `magazine` node rides the hand. The thumb goes from the hand guard's side to its place behind the magazine
  while the hand comes down off the hand guard (`_WAY_THUMB`), and on the magazine the four fingers close as one
  (`HandPoseModifier.open_together`; off the hand guard they open knuckles first).

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
degrees up and down, on both bodies, the right palm and thumb among the holding parts; the index finger within
12 mm of `Trigger` only while the rifle is up and more than 20 mm from it otherwise; the reload every half
hundredth; and on
the live player with simulated input, every update of idle, walk, sprint, aim, fire, crouch and crouched walk, the
reload by its key, and a switch to the pistol and back (never two weapons, never none, the rifle never shown without
both hands on it, the arms on its places before it shows and leaving after it hides). `test_hold_fit.gd` has the
male's fit put on and taken off with the model (his trigger finger's way with it), and `test_hand_pose_modifier.gd`
the order the fingers open in. `tests/gameplay/test_rifle_fingers.gd` (kit #1036) measures every finger of both hands
on the live player (its animation tree and the hold as they run, simulated keys and mouse, both bodies) in standing,
walking, sprinting, aiming, firing, crouched, crouched aiming and crouched walking, and the trigger finger's way at 50
steps of the raise on each body. `tools/capture/rifle_fingers_view.tscn` films six views from the game camera's eye
swung round the character (`RIFLE_FINGERS_BODY=male` for the other body).

Cost, headless on the desktop (`tools/bench/hold_cost.tscn -- rifle`, 40 mannequins, the least of five runs each on
a machine other agents were loading): the rifle's hold 77 microseconds a character a frame against 35 for the
pistol's aimed hold in the same session, so about 2.2 times it (the pistol's figure on a quiet machine is 12.6). It
is five modifiers and the hold's own `_process`; it is worked out on each machine from `aim_amount`, `view_pitch`,
the shots, the reload and the loadout's switch, never sent. Not measured in a browser yet.

Open: the mannequin's arm is short for this rifle's stock. For the left hand to reach the hand guard the butt sits
5 to 9 cm inside the front of the shoulder (the stock's deepest point against the torso's skin, both mannequins, low,
aimed and stowed; `pull_limit` takes it further in a sprint). From the game camera it is hidden; from the side the
stock's end is in the chest. A shorter stock on the model or a support place further back would cure it.

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
  and `HoldStage.settle()` waits for ever with no error after the first line. **Seen:** gdstudio #889, 2026-11-11.
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
- **Approach:** Make the test of a moving hand step as finely as the scan that found its faults (half a hundredth
  of the reload here), and give each finger the order that suits the part: knuckles first off a part the fingers
  are hooked over, all joints together onto a part they close round. **Watch out for:** at steps of 2 hundredths
  the test passed while the female's little finger swung 8.1 mm through the magazine's front between two steps
  (closing tips first, the order made for the hand guard), the male's thumb passed 5.4 mm, and a thumb still
  standing up while the hand crossed under the magazine well passed 17 mm. **Seen:** gdstudio #1040, 2026-11-11
  (fix: `open_together` on the magazine, `_WAY_THUMB`, `RELOAD_STEP` 0.005; 2.9 mm at most).
