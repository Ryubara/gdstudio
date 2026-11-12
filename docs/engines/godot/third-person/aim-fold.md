# The aim coming up and going down

<!-- new section: shooting.md reached its size limit; nothing held how the aim layer solves while the aim blends in -->

How the 3D Third Person aim layer turns the spine while the weapon comes up or goes down, so the chest never folds back.
Part of [the aim layer](shooting.md#aim-layer), which makes the modifier.

## Solved on the aim pose, not on the blend {#aim-fold}

<!-- new section: shooting.md reached its size limit; the solve while the aim blends in (gdstudio #1318) had no room
     there -->

While the weapon comes up or goes down the drawn pose is the aim pose blended with the carry pose, whose muzzle points
at the floor; a turn solved on it asks for up to 70 degrees of lift (115 at a look 30 degrees up) that the aim pose does
not need. So the layer hands the modifier the aim pose alone (`AimPose`: the hold's three aim clips read once at their
start and blended by `aim_pitch()` as the weapon layer's blend space blends them) and the modifier solves on that: the
chain and the arm down to the hand as the clips pose them, the hand as drawn (the grip has turned the wrist). From
`AimLayer.drawn_from` (0.9) of the aim up it moves to the solve on the drawn pose, which alone is exact once the weapon
is all the way up (the aim pose's turn and the drawn pose's differ by 2 to 3 degrees standing). The turn then comes on
by the aim's weight: standing, 0.3 degrees at a tenth of the aim where it was 83, and a shot from the carry, which keeps
the turn found before it, keeps a few degrees where it kept the whole lift (the pistol pointed at the sky through the
recoil).

The modifier works its passes out on copies of the chain's local poses and writes each spine bone once, because Godot
blends a modifier by `influence` from the pose before a bone's last write ([A clip on top of a pose a modifier fades
out](../animation-tree.md#a-clip-on-top-of-a-pose-a-modifier-fades-out)).

**What it costs** (`tools/bench/aim_layer_cost.tscn`). Once the weapon is all the way up the solve on the aim pose is
skipped, so a held aim costs what it did; the frames of an aim coming up or going down solve on both poses (five solves
instead of two, for about nine frames). The bench, `on` less `off` of the same code, on a loaded machine: 36 and 45
microseconds a character before, 19 and 42 after (a third pair was spoiled by load).

**The test** is `tests/gameplay/test_aim_fold.gd`: on every frame of an aim going up and coming down, standing at three
pitches, crouched, lying and through a shot from the carry, the chest turns at most the aim's weight times the full
aim's turn and 3 degrees; a probe modifier just before the layer records the chest, read again at `skeleton_updated`.
`drawn_from` is pinned in `test_aim_layer.gd`. **The capture** is `tools/capture/aim_fold_tour.tscn` (an aim in and out
standing and crouched and a shot from the carry, from the game camera; record at 60 frames a second and play at 15).

- **Approach:** Solve an aim offset on the pose it is meant for (the aim pose alone, read from the aim clips), not on
  the pose drawn while the aim blends in, and let the drawn pose take over only once the weapon is nearly up; apply the
  result by the aim's weight. Test every frame of an aim going up and coming down, and a shot from the carry, reading
  the chest at `skeleton_updated`. **Watch out for:** the drawn pose of the first and last frames of an aim is mostly
  the carry pose, so the solve asked for a 70 degree lift there, and with each bone written once per pass the
  `influence` did not scale it: the chest folded back by 80 degrees at a tenth of the aim, and a hip shot held that
  lift through its recoil. The layer's own tests read only frames at full aim. **Seen:** gdstudio #1318, 2026-11-11
  (`test_aim_fold.gd`, found by the Blender artist on PR #1315).
