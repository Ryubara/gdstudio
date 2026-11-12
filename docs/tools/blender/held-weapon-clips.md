# Clips that hold a weapon

<!-- new section: these entries left animation.md#solved-clips, which went over 50 KB when main's prone clips for the
form bodies (#1323) met this branch's prone aim and reload entries (gdstudio #1191, #1265) -->

A clip in which the hands hold a weapon is solved like any [clip solved from targets](animation.md#solved-clips), with
the weapon's hold taken from the game. The entries below come from the 3D Third Person pistol's prone aim and prone
reload (`templates/3d-third-person/game/assets/animation/prone/build_prone_aim_clips.py` and
`build_prone_reload_clip.py`).

## Solving on the game's hold {#on-the-games-hold}

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
- **Approach:** When a clip is solved again on another body, take nothing typed for the old one: rest each arm on
  the floor frame by frame (turn the elbow's pole up until the skin is over it), search the elbow's direction for a
  wrist the hold turns (bend and overlap together), and lift the weapon while a hand leaves it down its grip.
  **Watch out for:** the reload solved on the Quaternius female left the prototype bodies' left hand 8 and 25 mm
  off its place; its typed elbow height and pole then put the thinner right arm 16 mm and the left hand 13 mm
  under the floor; the pole that bent the returning wrist least put the upper arm 28 to 49 mm through the head.
  **Seen:** gdstudio #1185 (PR #1265), 2026-11-12 (one file a body; `Reload.frame`, `pole_return`, `let_go_lift`).
- **Approach:** When a held pose gets its two sides' own numbers, turn the support side ahead (the shoulder of the
  hand that reaches round the other), keep the firing arm the straighter one, and read both arms' stretch after
  every change of the trunk. **Watch out for:** the first uneven prone aim pushed the firing shoulder ahead, which
  took the support shoulder 4 cm back: the left arm was at 1.09 of its length and the hand 45 mm off the pistol;
  from above the first try (the pistol 12 mm off the middle, the chest turned 5 degrees) still read as a mirror
  until the pistol was 35 mm off and the chest turned 8. **Seen:** gdstudio #1111 (PR #1191), 2026-11-11 (the
  build fails under 30 mm between the left elbow and the right one's reflection).
- **Approach:** Solve a clip that shares a hand with a game modifier from the modifier's own plan (ported, its
  numbers dumped from Godot): the bone on the modifier's place where its weight is 1, and a pose right by itself
  where the weight is between, since the game blends the two there. **Watch out for:** the clip kept a fist until
  the hold let go, and the blend with the hold's opened hand put a fingertip 2.5 mm into the pistol at share 0.08;
  the hold's way off the pistol leads down, into the floor under a lying body (26 mm) unless the pistol rises
  first. **Seen:** gdstudio #1185, 2026-11-11 (`build_prone_reload_clip.py`, `test_prone_reload_hold.gd`).
- **Approach:** Take a free hand between two far places on a curve round the body, let the hand follow the forearm
  in mid-swing, and place a hand beside the body from the skin's width where the whole hand lies, with its fingers
  as curled as the clip will have them. **Watch out for:** a straight line from the belt to the pistol passed
  through the hand's own shoulder and the head (34 to 59 mm inside); a hand's world turn blended between the two
  ends while the forearm swung half a turn bent the wrist 154 degrees; a wrist placed 3 cm outside the waist had
  its curled fingers 50 to 105 mm inside the pelvis and the thigh, which is wider than the waist. **Seen:** gdstudio
  #1185, 2026-11-11 (`BELT_SWING`, `hand_free`, the belt measured over the hand's span; the limb check found all
  three before any render).
- **Approach:** Run the whole suite before the pull request opens when a clip or an export is added: the template
  pins the number of clips and every export of the pistol's definition. **Watch out for:** the related suites
  passed and the pull request was opened while the full run was still going; it then failed on the clip count (93,
  now 94) and on the pistol's pins, which lacked `prone_reload_clip`. **Seen:** gdstudio #1185, 2026-11-11
  (`test_character_clips.gd`, `test_weapon.gd`).
- **Approach:** Keep the poses of one blend near each other and a reaching arm short of straight, and test the
  blend between them in the game, not only each clip. **Watch out for:** the game blends bone rotations, not hand
  places: with the up pose 14 cm higher than the level one and the left arm at 0.99 of its length, the blend at 12
  degrees left the hand 16 mm short of its marker and the barrel 4 degrees off; at 7 cm and 0.97 both are inside
  the limits. **Seen:** gdstudio #1111, 2026-11-11 (`test_prone_aim.gd`).
