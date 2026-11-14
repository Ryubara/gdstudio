# The aim coming up and going down

<!-- new section: shooting.md reached its size limit; nothing held how the aim layer solves while the aim blends in -->

How the 3D Third Person aim layer turns the spine while the weapon comes up or goes down, so the chest never folds back.
Part of [the aim layer](shooting.md#aim-layer), which makes the modifier.

## Solved on the aim pose, not on the blend {#aim-fold}

<!-- new section: shooting.md reached its size limit; the solve while the aim blends in (gdstudio #1318) had no room
     there -->

While the weapon comes up or goes down the drawn pose is the aim pose blended with the carry pose, whose muzzle points
at the floor; a turn solved on it asks for up to 70 degrees of lift (115 at a look 30 degrees up) that the aim pose does
not need. So the layer hands the modifier the aim pose alone (`AimPose`) and the modifier solves on that. `AimPose` is
the pose the tree draws once the weapon is all the way up, worked out from the clips: the hold's three aim clips read
once at their start and blended by `aim_pitch()` as the tree blends them ([a blend worked out by
hand](../animation-tree.md#a-blend-worked-out-by-hand)), a bone a clip has no track for at its rest (our own aim clips
key no `spine_01`), the `AimBrace` on the first bone of the upper body by its share at full aim (its weight over the
aim's), the hand turned by the grip's wrist turn (`HandPose.turns` of `WeaponHold.grip_modifier()`, on top of the aim
clips' hand), and lying, the weapon's prone aim clips (`prone_aim_clip` and its down and up clips, by
`prone_aim_angles` and the prone state's look) by `CharacterAnimation.prone_hold_share()`. From `AimLayer.drawn_from`
(0.9) of the aim up the modifier moves to the solve on the drawn pose. The two agree to 0.1 degrees standing at three
pitches, crouched, lying and one-handed, so the turn comes on by the aim's weight alone: 0.3 degrees at a tenth of the
aim where main turned 82, and a shot from the carry keeps the full aim's few degrees where main kept 52 (the pistol
pointed at the sky through the recoil).

The modifier works its passes out on copies of the chain's local poses and writes each spine bone once, because Godot
blends a modifier by `influence` from the pose before a bone's last write ([A clip on top of a pose a modifier fades
out](../animation-tree.md#a-clip-on-top-of-a-pose-a-modifier-fades-out)).

**What it costs** (`tools/bench/aim_layer_cost.tscn`). Once the weapon is all the way up the solve on the aim pose is
skipped, so a held aim costs what it did; the frames of an aim coming up or going down solve on both poses (five solves
instead of two, for about nine frames). The bench, `on` less `off` of the same code, on a loaded machine: 36 and 45
microseconds a character before, 19 and 42 after (a third pair was spoiled by load).

**The test** is `tests/gameplay/test_aim_fold.gd`: on every frame of an aim going up and coming down, standing at three
pitches, crouched, lying, one-handed standing and crouched and through a shot from the carry, the chest turns at most
the aim's weight times the full aim's turn and 1 degree (123 failures on main's layer); a probe
modifier just before the layer records the chest, read again at `skeleton_updated`.
`drawn_from` is pinned in `test_aim_layer.gd`. **The capture** is `tools/capture/aim_fold_tour.tscn` (an aim in and out
standing and crouched and a shot from the carry, from the game camera; record at 60 frames a second and play at 15).

- **Approach:** Solve an aim offset on the pose it is meant for (the aim pose alone, read from the aim clips), not on
  the pose drawn while the aim blends in, and let the drawn pose take over only once the weapon is nearly up; apply the
  result by the aim's weight. Test every frame of an aim going up and coming down, and a shot from the carry, reading
  the chest at `skeleton_updated`. **Watch out for:** the drawn pose of the first and last frames of an aim is mostly
  the carry pose, so the solve asked for a 70 degree lift there, and with each bone written once per pass the
  `influence` did not scale it: the chest folded back by 80 degrees at a tenth of the aim, and a hip shot held that
  lift through its recoil. The layer's own tests read only frames at full aim. **Seen:** gdstudio #1318, 2026-11-11
  (`test_aim_fold.gd`, found by the Blender artist on PR #1315); #1356, 11-12 (lying).
- **Approach:** Work a pose out from the clips the way the tree blends them, with every input the drawn pose has at
  full weight (a bone a clip leaves out at its rest, each modifier that runs before, the state's own clips), and test
  it in every state against the drawn pose at full weight, with a probe that prints both. **Watch out for:** after
  main replaced the clips and added a brace, the prone aim and the grip's wrist turn, the first draft of `AimPose` (one
  set of clips, `slerp` between two points, a missing bone left as drawn, the hand as drawn) was off by 5 degrees
  crouched, 14 standing and 20 lying, each from a different input; the test still passed with a 3 degree margin on
  the pre-merge clips. **Seen:** gdstudio #1318, 2026-11-12 (merging main into the fix; the margin is now 1 degree).
- **Approach:** After a recoil keeps the aim offset's turn, ease its last pass with the release (`eased`), and test
  the muzzle's line in the character's space through a jump with a shot against the ground's moves. **Watch out
  for:** the pass put back in one tick what the release spread out; a jump moves the pose 16 degrees under a kept
  turn, so the chest snapped 10 to 20 degrees (1239 degrees a second). **Seen:** gdstudio #1369, 2026-11-13
  (`test_jump_weapon_hold.gd`; the takeoff's older step: #1462).
