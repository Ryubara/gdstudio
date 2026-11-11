# The rifle in both hands

<!-- new section: shooting.md reached its size limit; the rifle's two-handed hold moved here whole (gdstudio #1258) -->

Part of [crouch, aim and shoot](shooting.md), after [weapon pickups and a two-handed hold](shooting.md#weapon-pickups).

## The rifle in both hands {#rifle-hands}

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
  `tools/hold/solve_rifle_hold.py` from the rifle's own triangles and both mannequins' skins (`dump_hold_rig.gd`, then
  `write_hold.gd -- <file> rifle`), so no number of them is typed.
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
  The `magazine` node rides the hand.

Measured on the skinned mesh against the rifle (`HandContact`, the same in every clip, since the fingers are absolute
and the arms reach their places):

| Hand | Deepest in | Holding part farthest off |
| --- | --- | --- |
| Female, right | 1.3 mm (1.2 on the trigger) | the palm 4.4 mm, the fingers 2.4 |
| Male, right | 1.4 mm (the palm) | a finger 4.6 mm, the thumb's tip 4.4 |
| Female, left | 1.0 mm | 2.2 mm |
| Male, left | 0.9 mm | 3.4 mm |

Before the rework the clip's fist stood 22 mm inside the grip with its fingers 8 to 17 mm in and the index finger off
the trigger, the left hand 14 to 45 mm inside the hand guard, and the left arm 5 to 98 mm short of its place in the
walk, jog and sprint clips. On the way between its places in the reload the left hand passes at most 4.4 mm
through the hand guard (measured every half hundredth; the test caps it at 6 mm, as the pistol's).

Tests, `tests/gameplay/test_rifle_hold.gd` with `tests/fixtures/rifle_stage.gd` (a mannequin and the hold posed by
hand): both hands within the 2 mm and 5 mm in six locomotion clips at the low ready and aimed, and with the view 30
degrees up and down, on both mannequins, the right palm and thumb among the holding parts; the index finger within
12 mm of `Trigger` only while the rifle is up; the reload every 2 hundredths; and on
the live player with simulated input, every update of idle, walk, sprint, aim, fire, crouch and crouched walk, the
reload by its key, and a switch to the pistol and back (never two weapons, never none, the rifle never shown without
both hands on it, the arms on its places before it shows and leaving after it hides).

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
