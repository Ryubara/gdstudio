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
(`CharacterPeek.show`). `NetWire.VERSION` 9. No part of it is culled by distance or by sight: a far player leaning out
reads through a scope as a near one does.

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
`intersect_shape` with a capsule a tick, six more while a wall holds it short, and the modifier's two passes over five
bones on each drawn frame, only while it leans.

**What it does not do yet.** A right-handed weapon stays to the right of the head: leaning left, the head clears an
edge before the muzzle does, so a left peek needs the edge a little closer than a right one (the capture's pillar is
0.64 m wide for that). Crouched with the rifle and leaning right, the right upper arm meets the chest's skin on the
close aim view.

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
shape on, and stands up with the entry back at 12 bytes. The capture is `tools/capture/peek_tour.tscn` (26 s from the
game camera: behind a pillar, the pistol then the rifle, standing and crouched, each side shot at a target past the
edge).

- **Approach:** Present the facing the test gave a body (`_present_facing()`) before reading its skeleton as the
  "before" of a move that turns the body to the view. **Watch out for:** `PlayArena.add_player` sets `facing` and not the
  model's turn, so the first lean (which turns the body as an aim does) spun the model half a turn and read the pelvis
  10 cm and a foot 19 cm off. **Seen:** gdstudio #1400, 2026-11-13 (`test_peek_lean_pose.gd`).
- **Approach:** Put an action on a mouse button only after checking that the node reading it sees the event: in
  `PlayerCamera._unhandled_input` the shoulder swap is checked before the click that captures the mouse. **Watch out
  for:** with the swap moved from Q to the middle button, the click branch took the event first and the swap never
  ran (`test_camera_shoulder.gd`). **Seen:** gdstudio #1400, 2026-11-13.
- **Approach:** Compare a predicting client's state with the server's by the command's `seq` each side stepped, not on
  the same physics frame. **Watch out for:** the server steps a command a tick or two after the client, so on one frame
  the lean differed by a tick's growth (1/12) while every command matched exactly. **Seen:** gdstudio #1400, 2026-11-13
  (`test_peek_lean_online.gd`).
