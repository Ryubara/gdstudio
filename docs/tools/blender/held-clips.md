# Clips that hold a weapon

<!-- new section: moved from animation.md#solved-clips when that page reached 50 KB; how a clip that holds a weapon is
solved on each body with the hold the game uses -->

A clip that holds a weapon is solved from targets like any clip made from nothing
([Solved clips](animation.md#solved-clips)), and the weapon has to sit in the hands as the game holds it: the game's
hold seats the weapon on one hand and puts the other on a marker, so the clip is solved from that seat, a body at a
time. The 3D Third Person prone aim clips (`templates/3d-third-person/game/assets/animation/prone/build_prone_aim_clips.py`,
gdstudio #1111) are the first; how the game plays them is under
[The prone aim](../../engines/godot/third-person/moves.md).

## Solving a held pose {#solved-holds}

<!-- new section: the entries of the prone aim clips (gdstudio #1111), moved with the page -->

- **Approach:** Solve a clip that holds a weapon from the hold the game uses: dump the weapon's seat on the hand
  bone, the other hand's marker and the hand bones' rests from Godot (`tools/hold/dump_aim_seat.gd`), and put each
  hand bone where that seat carries the weapon, as a world turn from the rest (Godot's x, y, z to Blender's x, -z,
  y), so no bone axis of either program matters. **Watch out for:** a clip build that imports another
  (`import build_prone_clips`) reuses its rig, solver, keying and export, and a subclass adds what differs; the
  importer's key tolerance moves a pistol at the end of two stretched arms 2 to 4 mm through a breath the build
  holds to 0.5 mm. **Seen:** gdstudio #1111, 2026-11-11 (`build_prone_aim_clips.py`, `test_prone_aim_hold.gd`).
- **Approach:** Solve a clip that holds a weapon once for every body that plays it, one file a body, with that
  body's own hold, and measure in the build what the game shows: the hold's wrist turn and finger poses on (dumped
  from Godot with every bone's rest; fail when Blender's rests differ), the twist bones turned as the game turns
  them, the lower body read from the clip file the game plays under it. **Watch out for:** one set solved on the
  Quaternius female left the prototype bodies' left hand 3 to 27 mm off its marker with fingers 3 to 17 mm in the
  pistol, the elbow moved 58 to 100 mm and the magazine 8 to 26 mm under the floor; the build's skin had open
  fingers, so its floor numbers were not the game's. **Seen:** gdstudio #1111 (PR #1191), 2026-11-11 (fix:
  `--body` and `--idle` in `build_prone_aim_clips.py`; 1.2 mm in at most, Godot's skin within 0.1 mm of the build's).
- **Approach:** When a held pose gets its two sides' own numbers, turn the support side ahead (the shoulder of the
  hand that reaches round the other), keep the firing arm the straighter one, and read both arms' stretch after
  every change of the trunk. **Watch out for:** the first uneven prone aim pushed the firing shoulder ahead, which
  took the support shoulder 4 cm back: the left arm was at 1.09 of its length and the hand 45 mm off the pistol;
  from above the first try (the pistol 12 mm off the middle, the chest turned 5 degrees) still read as a mirror
  until the pistol was 35 mm off and the chest turned 8. **Seen:** gdstudio #1111 (PR #1191), 2026-11-11 (the
  build fails under 30 mm between the left elbow and the right one's reflection).
- **Approach:** Keep the poses of one blend near each other and a reaching arm short of straight, and test the
  blend between them in the game, not only each clip. **Watch out for:** the game blends bone rotations, not hand
  places: with the up pose 14 cm higher than the level one and the left arm at 0.99 of its length, the blend at 12
  degrees left the hand 16 mm short of its marker and the barrel 4 degrees off; at 7 cm and 0.97 both are inside
  the limits. **Seen:** gdstudio #1111, 2026-11-11 (`test_prone_aim.gd`).
- **Approach:** After merging main, read its diff for the hold a clip is solved from (the seat, the markers, a hand
  pose) and dump the hold and build the clip again when any of them moved. **Watch out for:** the hold moves the
  hands onto the weapon whatever the clip does, so the posed suites barely notice; a changed marker shows as an elbow
  pulled off the place the clip planted, and a new finger rule as a contact test written for the old one.
  **Seen:** gdstudio #1191, 2026-11-12 (after #1171's grip the left elbow moved 18 and 45 mm and the right thumb read
  7.5 and 10.1 mm off the gun, where it now rests on the left hand; rebuilt, 0.5 mm).
