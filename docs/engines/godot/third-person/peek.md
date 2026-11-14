# The peek lean

<!-- new section: the template page is at its size limit and no subpage covers a gameplay lean (gdstudio #1400) -->

## Leaning around cover {#peek}

<!-- new section: 3D Third Person had a gait lean (a pose into the turns, gdstudio #1159) and no gameplay lean; the peek
     lean around cover is a move of the body's step, with input, prediction, puppets and hits (gdstudio #1400) -->

The tactical shooter's lean: hold Q or E and the upper body tilts out past a wall's edge while the feet and the pelvis
stay, so the player sees and shoots around cover showing less of the body. It is not the gait's lean into its
acceleration and turns (`GaitLean`, `gds/Lean_*`, [the gait settings](clips.md#gait-settings)), which is a pose and
cosmetic; this one moves what the game decides with.

**Input.** `lean_left` (Q) and `lean_right` (E) in the project's input map; on a pad, the d-pad's left and right while
aim is held (`lean_left_pad`, `lean_right_pad`, bound beside the weapon switch, which the d-pad does only with the aim
down); on a phone the Lean L and Lean R buttons of `third_person_touch_controls.tscn`. Held or toggled: the player's
Settings > Controls > Toggle lean (`controls/lean_toggle`), else `PeekTuning.input_mode`. `PeekInput`
(`gameplay/player/peek_input.gd`) turns them into the command's held bits `lean_left` and `lean_right` (both at once lean
neither way); a toggled lean stands up when the body may not lean. E was interact and Q the shoulder swap: interact is
F now and the swap is the middle mouse button (the pad keeps its buttons).

**The step.** `CharacterPeek` (`gameplay/character/peek/character_peek.gd`), a module of `Character.step` like the
slide and the prone stance, runs after the move: `amount` goes toward the asked side (-1 left, 1 right) over
`lean_time`, and to 0 while sprinting on the move, sliding, vaulting, lying down or in the air; a death stands it up at
once. The whole lean is the tilt that puts the eye `side_offset` (0.35 m) to the side, never more than `max_angle` (30
degrees) standing or `crouch_max_angle` (45) crouched, about a pivot `pivot_share` (0.55) of the eye's height up:
0.349 m standing, 0.29 m crouched on the template's body. The eye point (the camera's target, where a shot without a
crosshair ray leaves) moves with it (`CharacterCapsule.fit` places it), the body walks no faster than `move_speed`
(1.2 m/s) and turns to the view as an aim turns it, and `PeekShape`, a capsule on the body along the bent spine from
`shape_start` of the bend to a radius above the eye, is enabled: a shot meets it outside the upright capsule and the
hit zones on the bent skeleton answer. Before the lean grows, that capsule (grown by `wall_margin`) is tried at the
whole lean and halved toward the last free share six times when it meets something (`room`); the lean is held at
`room`, so the head and the shape never go into a wall and the feet are never pushed (`CharacterLean.can_take` sends a
leaning body through the full tick). A weapon with no muzzle (a server's body) rolls its `no_muzzle_offset` with the
lean (`CharacterPeek.roll`).

**Online.** The lean is the player's command and state, never cosmetic simulation: two bits of the command's byte 13
(`CommandCodec.G_LEAN_LEFT`, `G_LEAN_RIGHT`), `amount` in `CharacterState.peek` (a predicting client puts it back and
steps it again as it does the slide), and while not 0 one signed byte at the end of the player entry (`F_PEEK`,
`PlayerEntry.peek`; 12 bytes, 13 aiming or leaning, 14 both), so a puppet shows the lean, its eye and its shape
(`CharacterPeek.show`). `NetWire.VERSION` 11 for the lean, 12 for its shot start on the left ([below](#left-shoulder)).
No part of it is culled by distance or by sight: a far player leaning out reads through a scope as a near one does.

**The bend.** `PeekLayer` (a node of `character_dressed.tscn`) makes a `PeekModifier` as the skeleton's first own
child, after the brace and the momentum blend, before the hold's and the aim layer's modifiers. It rolls `chain`
(`pelvis` to `neck_01`, shares 0.2, 0.25, 0.25, 0.18, 0.12) about the way the body faces, turns `keep` (the thighs) back
so the legs and the pelvis's place stay, and solves the roll in two passes so the `Head` bone goes where the step put
the eye. The hold then closes the hands where the bend took the weapon and the aim layer turns the bent chest back onto
the aim. On the template's body the head goes 0.345 m out and the upper body tilts about 34 degrees from the hips (its
hips are 0.91 m up and its head 0.61 m above them, so 0.35 m takes more than the 30 degrees of the eye's pivot).

**Inspector.** `Character` > Peek > `peek_tuning` (`PeekTuning`; the player's `gameplay/player/peek_tuning.tres`):
Lean `enabled`, `side_offset`, `max_angle`, `crouch_max_angle`, `pivot_share`, `lean_time`; Moving `while_crouched`,
`move_speed`; Body `shape_radius` (0.2 m), `shape_start` (0.45), `wall_margin` (0.03 m); Input `input_mode`.
`PeekLayer`: `chain`, `chain_weights`, `keep`, `head`, `disabled` (the body still leans, unbent).

**The cost.** On a tick with no lean and none asked for, the step is one comparison. A leaning body adds one
`intersect_shape` with a capsule a tick (about 7 us headless in the editor build), six more while a wall holds it short,
and the modifier's two passes over five bones on each drawn frame, only while it leans. A held lean places the eye and
the shape again only when the lean, the facing, the eye's height or the tuning changed. Forty bodies stepped by hand,
headless: 25 us a body a tick upright, 37 leaning (crouched: 26 and 37).

A left lean takes the weapon to the left side ([below](#left-shoulder)); with the rifle the arms stay out of the chest
on either lean ([the arms on a rifle lean](#rifle-lean-arms)).

**Proof.** `tests/gameplay/test_peek_lean.gd`: the eye goes 0.32 to 0.37 m to the side with the feet within 1 mm, over
a fifth of a second; both bits lean neither way; the shape stands for the shoulders and the head; a wall beside the body
stops the lean short with the shape clear of it and the feet unmoved; crouched it leans and walks at `move_speed`; a
sprint, lying down, a jump and a death end it; a snapshot puts it back; from behind a wall's edge the lean sees and
shoots a target the upright body cannot, on the server's bare body and on the dressed player; Q and E held and toggled,
the pad's aim and d-pad (no weapon switch) and a touch press lean; the command bits and the entry byte round-trip.
`test_peek_lean_pose.gd`: the head bone goes within 3 cm of the eye's shift with the pelvis and the feet within 1 cm;
aiming while leaning both ways the pistol and the rifle miss the aim by under 3 degrees with both hands within 5 mm of
their places (0.0 mm read); a shot at the leaning head meets the head zone where the upright body has nothing; the camera
goes to the lean's shoulder and back. `test_peek_lean_online.gd`: a predicting client and the server step the same lean
and eye command for command (0 difference), the shots are as many and leave within 10 cm of each other (the client's
muzzle as drawn, the server's rolled offset), and a watching client's puppet leans within one step of the byte, with its
shape on, and stands up with the entry back at 12 bytes, leaning right and leaning left. The capture is
`tools/capture/peek_tour.tscn` (26 s from the game camera: behind a pillar 0.8 m wide, the pistol then the rifle,
standing and crouched, each side shot at a target past the edge; `LEFT_SHOULDER=0` films the weapon right of the head).

- **Approach:** Present the facing the test gave a body (`_present_facing()`) before reading its skeleton as the
  "before" of a move that turns the body to the view. **Watch out for:** `PlayArena.add_player` sets `facing` and not the
  model's turn, so the first lean (which turns the body as an aim does) spun the model half a turn and read the pelvis
  10 cm and a foot 19 cm off. **Seen:** gdstudio #1400, 2026-11-13 (`test_peek_lean_pose.gd`).
- **Approach:** Put an action on a mouse button only after checking that the node reading it sees the event: in
  `PlayerCamera._unhandled_input` the shoulder swap is checked before the click that captures the mouse. **Watch out
  for:** with the swap moved from Q to the middle button, the click branch took the event first and the swap never
  ran (`test_camera_shoulder.gd`). **Seen:** gdstudio #1400, 2026-11-13.
- **Approach:** Time a per-tick module's parts one by one in a loop of thousands of calls before guarding engine calls,
  and skip the whole placement when what it is placed from has not changed. **Watch out for:** a leaning body first
  cost 28 us more a tick than an upright one; writing the capsule's size and the shape nodes' places only on a change
  saved under 1 us, because 9 of the 28 were the GDScript calls of `CharacterCapsule.fit` itself. Skipping the fit at
  a steady lean brought it to 12. **Seen:** gdstudio #1400, 2026-11-13.
- **Approach:** Compare a predicting client's state with the server's by the command's `seq` each side stepped, not on
  the same physics frame. **Watch out for:** the server steps a command a tick or two after the client, so on one frame
  the lean differed by a tick's growth (1/12) while every command matched exactly. **Seen:** gdstudio #1400, 2026-11-13
  (`test_peek_lean_online.gd`).

## The weapon on the left side {#left-shoulder}

<!-- new section: the template's weapons are right-handed and nothing moved them for a left lean; the hold that does is
     its own part, read by the rifle's hold, the pistol's and the server's shot (gdstudio #1435) -->

The template's weapons are right-handed. Leaning left, the head cleared a wall's edge before the muzzle did: aimed
ahead, a whole right lean holds the pistol's muzzle 0.36 m right of the body's middle and the rifle's 0.28 m, a left
lean held them 0.21 m left and 0.03 m right (the rifle still in the right shoulder), so a left peek needed the edge 0.16
to 0.25 m closer and its shot struck the edge it peeked past. Tactical shooters switch shoulders for it; the template
does too, by `CharacterPeek.shoulder_share()` (the left lean as drawn, eased; the step's `amount` for a server's shot):

- **The rifle** goes to the left shoulder: `TwoHandHold.side` mirrors the shoulder's pocket (its x), the gun's turn
  across the body (`LeftShoulder.mirrored()`: the yaw and roll of the turn change sign) and turns the chest toward
  `left_chest_turn` (10 degrees, nearly square on; [the arms](#rifle-lean-arms)). The hands stay on their places on
  the rifle, so the right hand reaches across the chest to the grip and the left arm forward to the hand guard; the
  head's sight goal follows the rifle's `AimEye`.
- **The pistol** goes across the face to the left eye: `LeftShoulder` (a node of `character_dressed.tscn`) makes a
  `LeftShoulderCross` and a `HoldArm` on the right arm right before the hold's support arm; while the pistol is aimed
  (the hold's aim weight, less a reload and the rack) they move the right hand `pistol_shift` (0.19 m) to the left
  across the leaning chest (left and down by the bend's roll) and turn it about the muzzle so the muzzle stays on the
  aim layer's aim point. The support arm runs after them and closes the left hand where the pistol went.
- **A weapon with no muzzle** (a server's body) mirrors its `no_muzzle_offset` sideways by the same share
  (`CharacterPeek.lean_offset()`, after the lean's roll), so a predicting client's shot and the server's leave within
  4 cm of each other on a left lean as on a right one.

Aimed ahead, a left lean now holds the pistol's muzzle 0.361 m left (the right lean's 0.364 m right) and the rifle's
0.297 m (0.283). The fingers are solved on the weapon, not on the body, so the grip, the trigger finger and the support
hand close on it as they do on the right (0.0 mm from their places in every frame of the way across). A pose on each
machine from the lean the body already has: never sent. Off: `PeekTuning.left_shoulder` (the rifle, the pistol and the
server's shot), `LeftShoulder.disabled` (the pistol alone).

`tests/gameplay/test_peek_left_shoulder.gd`: aimed ahead, the left lean's muzzle is within 4 cm of the right lean's
mirrored, both hands on their places and the aim under 3 degrees off, for the pistol and the rifle; the same over a
lean to the left, to the right and upright tick by tick; from one spot behind a pillar a left lean and a right lean
each hit a target past their edge, and neither strikes the pillar, with the pistol, the rifle and on the server's bare
body. Without the hold the muzzle cases and the three pillar cases fail (the left shot struck the pillar). The online
case of `test_peek_lean_online.gd` runs leaning left too. Close-ups: `tools/capture/left_shoulder_closeups.tscn`
(`CLOSEUP_WEAPON`, `CLOSEUP_SIDE`, `LEFT_SHOULDER=0`).

- **Approach:** Measure where a weapon's muzzle is on both leans, aimed ahead, before choosing how to move it, and
  move only the weapon's place: let the hold's own reach put the hands on it. **Watch out for:** the rifle's chest
  turn mirrored with its pocket (30 degrees, the right shoulder forward) left the left shoulder so far back that the
  left hand stopped 15 mm short of the hand guard; square on (0 degrees) both hands reach (0.0 mm). **Seen:** gdstudio
  #1435, 2026-11-13 (`left_chest_turn`).
- **Approach:** Move a weapon to the other side across the leaning chest, along the bend's roll, not level.
  **Watch out for:** a level move put the left lean's pistol 20 cm higher than the right lean's mirror (the bend
  drops the right side on a right lean), and the server's mirrored shot start left 13 cm under the client's.
  **Seen:** gdstudio #1435, 2026-11-13 (`test_peek_lean_online.gd` leaning left).
- **Approach:** Step a close-up capture's body by commands (`CommandDriver.take`, `step()` each tick), not by input
  actions, when the camera moves round it. **Watch out for:** with the actions pressed the player's input turned the
  aiming body to the close-up camera's view, so the body spun as the camera went round the hands. **Seen:** gdstudio
  #1435, 2026-11-13 (`left_shoulder_closeups.gd`).

## The arms on a rifle lean {#rifle-lean-arms}

<!-- new section: the peek page said how the body bends and the weapon changes sides; nothing covered how the rifle's
     stance meets the bend, which put the right arm into the chest (gdstudio #1436) -->

Aiming the rifle and leaning, the right arm went into the chest: 29 to 42 mm crouched, 4 to 47 mm standing on a right
lean, and 31 to 72 mm on a left one, while the upright aim had none (`BodyClearance.arms_in_torso()`, both prototype
bodies). The cause was two turns of the chest that do not know about each other. The bend rolls the chest about the
model's front (about 60 degrees at `spine_03` for the eye's 0.35 m); the rifle's stance then raises a chest that leans
more than `aim_lean_limit` the short way, about the axis between the chest's up and the world's, and on a chest the
crouch bends forward that axis is a diagonal: the raise swung the shoulders round to 55 to 58 degrees from the front
standing and 78 to 84 crouched, against the hold's `chest_turn` of 30. The stance had set that turn first, read from
the chest's forward axis, which the roll leaves pointing ahead, so it saw nothing wrong. With the left shoulder
forward of the gun, the grip was ahead of the right shoulder and to its left, and the arm reached across the chest.

Now the stance turns the chest again after the raise (`two_hand_stance.gd`, `_turn_back`), by the lean's share (the
character's drawn lean either way; `TwoHandStance.lean_share` for a figure posed by hand): it reads the turn from the
shoulders' line (the chest's side axis) and turns the spine and the head back by what is left to the hold's turn
(`chest_turn`, or `left_chest_turn` by `side`), as the first turn does. An upright body is left as it was. On the left
shoulder the right hand still reaches across the chest, and there two more things take the arm out: the right elbow
points toward `RightPoleLeft` (a marker of `two_hand_hold.tscn`, high and forward of the chest) by `side` instead of
`RightPole` (`HoldBones.pole()`), and the chest stands at `left_chest_turn` 10 degrees, the right shoulder a little
forward (square on, the female's right arm was still 3 to 8 mm into her chest; at 15 the left hand came 1.3 mm off its
place). Every case now measures 0.0 mm, both hands stay on their places (under 1 micrometre) and the aim layer keeps the
muzzle on the aim. A pose on each machine from the lean the body already has: never sent.

`tests/gameplay/test_peek_lean_arms.gd` reads the drawn pose after the hold's modifiers for twelve updates, upright and
leaning each way, crouched and standing, on both bodies: no vertex of the upper arms and forearms (the hands, which
hold the rifle, and the shoulder's own skin within `BodyClearance.SHOULDER`, 8 cm of the upper arm's bone, left out)
deeper than 4 mm in the torso's skin, nor the rifle more than 10 mm; on the old hold it fails 9 times. The tour films
it from the front too (`PEEK_VIEW=front`, `PEEK_BODY=male`).

- **Approach:** After every modifier that turns the chest another way (a raise, a lean), read the shoulders' line, not
  the chest's forward axis, and turn back to the hold's chest turn last. **Watch out for:** a roll about the front
  leaves the forward axis ahead, so a stance that reads it sees no turn while a later raise of the rolled chest swings
  the shoulders 25 to 54 degrees past it; moving the right elbow's pole, letting the pocket follow the lean and canting
  the gun with the roll each left the arm 20 to 60 mm in the chest, since the grip was across it. **Seen:** gdstudio
  #1436, 2026-11-13 (a probe modifier after each of the skeleton's modifiers found the turn in `PeekBend` and the
  stance).
- **Approach:** Measure an arm in the body with the arm's own skinned vertices against the torso's skin alone (a ray's
  crossings with the torso's triangles), leaving out the shoulder's skin near the upper arm's bone. **Watch out for:**
  the shoulder's skin meets the chest's in every pose, so counted it read 12 to 24 mm on the upright aim and hid the
  lean's own 30 mm. **Seen:** gdstudio #1436, 2026-11-13.
- **Approach:** Aim a capture tour's shots at the middle of their target and print where each one meets it.
  **Watch out for:** the peek tour's crouched shots met the boards' lower edge (0.5 m below the middle at 10 m), so a
  10 degree change of the left shoulder's chest turn made the crouched left shot miss below; the pitch is now
  `CROUCHED_PITCH`. **Seen:** gdstudio #1436, 2026-11-13.
