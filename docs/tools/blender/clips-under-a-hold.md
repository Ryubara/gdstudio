# Clips under a hold

<!-- new section: moved from animation.md#clips-under-a-hold when a merge of main put that page over 50 KB; how to
key a body for a weapon that the game's own modifiers place after the clip (the 3D Third Person rifle, kit #1082) -->

How a clip is keyed for a weapon the game carries after the clip, which [Animation](animation.md#solved-clips) left
when it passed 50 KB.
A clip solved with the weapon already in the hands, from the hold's seat and markers on each body (the prone aim),
is under [Solving a held pose](#solved-holds).

## The body under the hold {#body-under-the-hold}

The 3D Third Person rifle is not on a bone: `TwoHandHold` places it from the chest bone after the clip, turns the
chest, reaches the arms and closes the fingers. Its six clips
(`templates/3d-third-person/game/assets/animation/rifle/build_rifle_clips.py`: idle, three aims, a shot, a reload)
are the body under that.

- **Work the game's hold out in the build, from the game's own files.** The build reads the hold's exported numbers
  from its script, the hands' places from its scenes and the finger poses from their resources, and runs the same
  steps on its own skeleton (the chest turn and its straightening, the pocket in the chest's frame, the left
  collarbone's reach, the butt brought to the torso's skin from points over the body's own triangles, the pull
  along the barrel, the two-bone reach, the fingers, the reload's way). The body is then shaped round the rifle
  where the game will draw it, the arms it keys are the hold's, and the same code poses the other body for the
  checks, with the hold solved on that body (its `HoldFit`). A Godot test proves it is the same hold: the clip's
  own hand against the hold's, on a key (1.6 mm on the prototype female; the game settles the butt's push over
  frames, to within 3 mm).
- **Key over the pose the game holds under the clip.** A clip keys each bone in its parent, so arms keyed to reach
  a place the hold sets in the model's space are right over one pelvis only. The build stands on the game's
  standing idle at its steadiest frame (the frame `AimStance` holds the legs on under an aim) and writes the clip
  and the time into its data file, which the Godot test poses before it compares.
- **Pose the bones the engine drives.** The prototype rig's twist bones are turned by a modifier in the engine and
  keyed by no clip; the build turns them the same way before it measures or draws the skin, and keys only the
  bones a clip may key (not the root, a `_leaf`, a twist bone, a socket or an `ik_` target).
- **Stand the trunk, the neck and the head from the rest pose, not from a library pose.** The library's `Idle` has
  the chest 16 degrees forward and 13 turned, and the head 14 down; turns added on top of it bowed the head 40
  degrees. The legs and the pelvis are the idle's; everything above is stood upright and turned from there, the
  neck and the head in the character's space, so a breath or a recoil under them does not move the look.
- **The head of an aim is the game's, so key the game's.** The game sets an aiming character's neck and head
  after the clip (`AimHeadModifier`: level for a pistol, toward the sights for the rifle). The build runs the same
  rule with the modifier's own numbers and the weapon's `AimEye` marker (`sight_head`) and keys that, so the file
  shows what the game draws and the skin against the stock is measured on the head the player sees (the game's
  standing head is within a degree and a millimetre of the build's).
- **A shot is added, not played over.** A recoil clip made on the level aim replaces an aim up or down while it
  plays. In Godot the one-shot adds (`MIX_MODE_ADD`) an `AnimationNodeSub2` of the clip less the same clip held on
  its first frame (a time scale of 0), which is the aim pose it was made on.
- **Measure the weapon against the body too.** The limb check knows limbs; the build also casts the head's and the
  chest's skin against the rifle's mesh where the hold has it, and measures what the hold does with no clip of
  yours under it, as the floor to hold a clip to.

- **Approach:** Give a pose search limits a body has (so many degrees of lean, of neck) as steep costs, weigh the
  target against them, and read the solved angles before the picture. **Watch out for:** a free least-squares put
  the eye on the sight line with the neck 88 degrees down and the head 70 back, and with the limits off the trunk
  leant 44 degrees; the eye could not get there at all: the pocket is 12 cm under an upright eye and the comb 7 cm
  under the line. **Seen:** gdstudio #1082, 2026-11-11 (fix: `AIM_LIMITS`; the eye ends 5 to 7 cm over the line
  with the head on the comb, written in the clips' README).
- **Approach:** Keep skin off a weapon in a search with points of every bone that can touch it, from every model
  that plays the clip. **Watch out for:** head points alone left the neck 7.5 mm in the stock, and a search on the
  female head left the male's wider one 10 mm in. **Seen:** gdstudio #1082, 2026-11-11 (fix: `SKIN_POINTS`, the
  head and the neck of both).
- **Approach:** Before tuning a clip against a limb check, measure what the game does without the clip, and try the
  shoulders. **Watch out for:** the hold alone has the right forearm 24 to 28 mm in the ribs at the low ready (the
  grip is close to the chest, kit #1177); an upright chest made it 28 and 44 mm, and no elbow pole cured the
  female; rounded shoulders and a raised right collarbone brought it to 17 and 20 mm. **Seen:** gdstudio #1082,
  2026-11-11 (the build's `hold_alone` floor).
- **Approach:** Compare a clip's own pose with what a modifier makes of it on the clip's keys. **Watch out for:**
  between two keys a fast hand is a chord off its arc: the reload's hand read 4.9 mm off at a share between keys and
  1.2 mm on them. **Seen:** gdstudio #1082, 2026-11-11 (`test_rifle_clips.gd` rounds the share to a frame).
- **Approach:** After adding a clip library or an export to a resource script, run the whole template suite before
  opening the pull request, not only the new suite. **Watch out for:** two older tests pin what the change widens:
  `test_character_clips.gd` counts every clip of every library (90 became 96) and `test_weapon.gd` wants a pinned
  default for every `WeaponDef` export (`shoot_additive`). And a pull request stacked on another carries that one's
  commits: its `Model:` line names every model in their trailers. **Seen:** gdstudio #1267, 2026-11-11 (the
  `template (3d-third-person)` and `commits` checks failed on the first push).
- **Approach:** When the idle under a clip or the bodies that play it change, rebuild the clip over the new idle on
  the new bodies and run the test that compares the clip's own hands with the hold's first. **Watch out for:** the
  clips were keyed over the library's `Idle` on the Quaternius female; the template then moved to its own idle and
  the prototype bodies, and the clip's own hands stood 68 to 158 mm from the hold's (the pelvis under them tips
  another way, and each bone is keyed in its parent), while every test of the hands on the rifle still passed,
  because the hold moves the arms. Only the own-arms test saw it. **Seen:** gdstudio #1267, 2026-11-12 (fix:
  `BASE_CLIP`, `library_pose()`'s steadiest frame, `base` in `rifle_clips.json`; 0.9 mm).
- **Approach:** When the hold a build mirrors changes on `main`, port every step of its diff that moves the weapon
  or a bone, build, and read what the search solved and where the weapon ended before any test; a state the hold
  settles over frames (the push) is worked out to its settled value. **Watch out for:** after the hold gained the
  push to the skin, the collarbone's reach and a pocket 4 cm farther out, the old clips passed every hand test (the
  hold moves the arms) while the build's rifle was 4 to 10 cm from the game's; ported, the head search ran the neck
  to its limits with the eye 5 to 8 cm off the line, and the clips' lean now moves the rifle (44 mm at a level
  aim). **Seen:** gdstudio #1267, 2026-11-12 (fix: `Hold.straighten`, `chest_frame`, `measure_chest`,
  `butt_push`, `reach_shoulder`; own arms 1.6 mm; the eye's limit 80 to 90 mm).
- **Approach:** Cut the skin you measure against a weapon where the weapon's own place is: the head for the comb,
  the neck's base and the chest for the butt, each its own number. **Watch out for:** the limb check's `head` part
  is the head and the whole neck; on the prototype male one vertex of the neck's base read 9 to 13 mm in the butt's
  top corner and failed the head's limit, though the head was 0 mm in and no neck angle moves that vertex: it is
  the hold's pocket. **Seen:** gdstudio #1267, 2026-11-12 (fix: `HEAD_SKIN`, `neck_in_rifle_mm` reported with the
  chest's).
- **Approach:** Before blaming a clip for a pose in a game capture, record the same seconds with the clip taken out
  of the weapon's definition. **Watch out for:** the trunk twists about 70 degrees to the right for three frames as
  the rifle is drawn after a walk into its pickup; the capture with `main`'s `rifle.tres` (no rifle clip) has the
  same three frames, so it is the switch's, not the clips'. **Seen:** gdstudio #1267, 2026-11-12.

## Solving a held pose {#solved-holds}

<!-- new section: folded in from held-clips.md, which gdstudio #1191 split from animation.md#solved-clips at the same
time as this page; a clip solved with the weapon in the hands on each body, from the hold's seat and markers (the
prone aim, gdstudio #1111) -->

The 3D Third Person prone aim clips (`templates/3d-third-person/game/assets/animation/prone/build_prone_aim_clips.py`)
are solved from the pistol's hold as Godot dumps it (`tools/hold/dump_aim_seat.gd`), one file a body; how the game plays
them is under [Prone and the crawl](../../engines/godot/third-person/moves.md#prone).
The prone reload (`build_prone_reload_clip.py`, gdstudio #1185) is solved the same way, from the hold's own reload: its
entries, folded in from that pull request's `held-weapon-clips.md`, follow the aim's.

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
  7.5 and 10.1 mm off the gun, where it now rests on the left hand; rebuilt, 0.5 mm); again after #1262's seat (a
  little finger 6.4 to 9.0 mm under the floor and the left elbow off; rebuilt, `test_prone_aim_hold.gd` green).
- **Approach:** When a build carries the hold's plan in its own code (the prone reload's `ReloadHold` is
  `SupportHandPlan` in Python), port main's diff of the plan and of the hold's `refresh`, extend the dump by what
  the port reads, and give anything new in the hand its own measure before the pose is tuned again. **Watch out
  for:** a fresh dump alone left the build on the old plan: the clip's arm took the hand 41 mm early, where the
  hold now waits for the right thumb; the magazine's new 12 cm way in put the left hand 30 to 38 mm under the
  floor under a pistol canted 45 degrees, and canted 65 the hand came back on with its wrist bent 86 to 90
  degrees. **Seen:** gdstudio #1185 (PR #1265), 2026-11-12, after #1171, #1262 and #1306 (279 failed checks on the
  old files; fix: `ARM_UNTIL`, `down_back`, the carry poses, `CANT_IN`, `CANT_OUT`, `magazine_points`).
- **Approach:** When a clip is solved again on another body, take nothing typed for the old one: rest each arm on
  the floor frame by frame (turn the elbow's pole up until the skin is over it), search the elbow's direction for a
  wrist the hold turns (bend and overlap together), and lift the weapon while a hand leaves it down its grip.
  **Watch out for:** the reload solved on the Quaternius female left the prototype bodies' left hand 8 and 25 mm
  off its place; its typed elbow height and pole then put the thinner right arm 16 mm and the left hand 13 mm
  under the floor; the pole that bent the returning wrist least put the upper arm 28 to 49 mm through the head.
  **Seen:** gdstudio #1185 (PR #1265), 2026-11-12 (one file a body; `Reload.frame`, `pole_return`, `let_go_lift`).
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
- **Approach:** When the clip under a layered clip is rebuilt (the prone idle under the aim and the reload), build
  every clip solved on it again in the order they join (the aim, then the reload), and compare a file read back with
  a solved pose over the bones the file keys only. **Watch out for:** the merge of main's prone clips for the
  `form` bodies left the aim and reload files solved on a pelvis 42 mm higher: the posed suites passed and only the
  live reload read the left hand 14 mm and the magazine 28 mm under the floor; the base build had stopped keying
  twist bones, so the reload's join check read 127 degrees between its turned twist bones and the file's rests.
  **Seen:** gdstudio #1185 (PR #1265), 2026-11-12, after #1323 (`--idle prone_form_<body>.glb`, `rig.extra`).
