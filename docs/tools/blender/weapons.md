# Weapons in the Toon Shooter style

How to build original weapons that sit beside the Quaternius Toon Shooter kit (CC0) and drop into its characters'
hands. Learned on Deadnight's first four weapons ([Deadnight #16](https://github.com/Ryubara/deadnight/issues/16));
the scripts are in Deadnight's `tools/blender/` (`build_weapons.py`, `weaponlib.py`, `render_turntable.py`,
`render_hold.py`), and the game's numbers are in its style bible and `docs/research/weapons.md`.

## Axes, origin and the hold {#axes-origin-and-the-hold}

The kit characters carry every weapon as a mesh parented to the right hand's `Index1.R` bone, origin on the bone.
The copy in the hand uses the standalone file's own mesh data, so a weapon that follows the kit file's frame drops into
the same hold:

| Kind | Axes (Blender; the glTF is the same with Y up) | Origin |
| --- | --- | --- |
| Guns | muzzle along -X, up +Z, thin across Y | the grip, behind the trigger (72-89 % along from the muzzle) |
| Melee | standing up along +Z | the grip, near the handle end (13-40 % of the length) |

Copy the hold from a kit weapon that is unit-scale in the character file: the **Shotgun** for long guns, the
**Shovel** for melee (offset about 2 mm from the bone). The AK and Sniper copies carry rescaled mesh data (object
scale 0.21-0.42), so their transform does not carry over to a weapon at true size. Prove each new weapon with a render
of the character holding it beside the kit one. A kit hold puts the weapon in the hand, but not the fingers on it:
for that, solve each weapon's grip from its own sockets ([Hands on the weapon](#hands-on-the-weapon)).

**Hand guns.** The kit file's Revolver copy is rescaled like the AK's, so use the Shotgun hold for every gun, and size
one-handed guns against the hand ([Hands on the weapon](#hands-on-the-weapon)). Sweep a bent bar as one tube;
boxes give a bend a saw-tooth edge.

**Thrown weapons.** The kit characters carry no kit grenade, so a grenade has no kit hold to copy. Model it standing up
along +Z with the origin in the body's centre (the fist), and give each moving part its own node, origin at its
pivot (Deadnight's `Pin` slides out, its `Spoon` swings off its hinge). In Godot the gun hold turned 90 degrees about
the weapon's X (`HOLD_GUN * Basis(Vector3.RIGHT, PI / 2)`) stands it fuze up in the fist; the turn that looks right
in a Blender preview against the kit copy is a different one, so choose the hold from candidates rendered in Godot.

- **Approach:** Give each held item a grip, support and barrel check in tests and a side, shoulder and aim capture.
  **Watch out for:** weapons were attached once and never checked against the hands, the shoulder and the aim ray, so
  guns sat at the wrong scale, angle and place on the player. **Seen:** Deadnight, 2026-11-01 (fix: the checks and
  captures above for every held weapon ([Hands on the weapon](#hands-on-the-weapon))).
- **Approach:** Scale every held item by one written rule against the character's in-game height, test grip, support
  hand, stock and barrel for each weapon, and capture each weapon in the hands. **Watch out for:** the guns were
  modelled at real length while the player scene scales the Soldier to 0.8 (the rifle was as long as the Soldier is
  tall), held from a one-handed pose with the barrel 21 degrees up, and every gun showed the rifle because nothing
  called `equip`. **Seen:** Deadnight #288, 2026-11-01 (fix: measuring hands, stock and barrel against the aim ray found
  all three).

## Attachment points {#attachment-points}

Where an effect or a hand meets a weapon is part of the model, so **attachment points are the modeller's job**: whoever
builds a weapon places them in Blender, and gameplay code reads them instead of typing offsets from the body.

- **Every firearm carries an empty named `Muzzle`** at the centre of the barrel's open end, parented to the weapon's
  root, with **-Z pointing out of the barrel** (Godot's forward). In Blender that is the empty's local **+Y**: the glTF
  export turns Blender +Y into -Z. For a gun along Blender -X, turn the empty 90 degrees about Z
  (`rotation_euler = (0, 0, pi/2)`); it arrives in Godot turned 90 degrees about Y, -Z along the barrel.
- **Two barrels side by side get one `Muzzle` centred between them**, at the barrels' end face.
- **Melee weapons and grenades get none.**
- **A gun with an ejection port carries `Eject`** at the port's centre, keeping the weapon's own axes: its local
  +Y is the gun's right side in Blender, so its -Z in Godot points out of the port (Deadnight #786, for a case
  effect).
- **Every level of detail carries it at the same point**, so the flash does not jump when the far level swaps in.
- **A test proves it:** load each firearm's file, find `Muzzle`, check it sits within 1 cm of the bounds' front face
  along the barrel and points along it. Deadnight's is `game/tests/art/test_weapon_muzzle.gd`, built by its
  `build_weapons.py` (`MUZZLES`) and drawn by `render_muzzle.py`.

**Tools swung by a clip.** A tool that only an action clip swings (Deadnight's repair hammer, #326) takes the melee
hold and then a turn chosen from the clip itself: trace the striking face through one loop for a few turns about the
handle and tips in the swing plane, and keep the one whose face points along the blow and toward the target at the
lowest point. For the Soldier's `Repair_Board`, the bat's hold already faced the board; a 20-degree tip in the swing
plane squared the face to the downward blow. Draw a small tool large (the kit's knife is 1.4 m, longer than its
shovel), and size it in the hand for the fist: a hammer at the size rule's 0.29 m vanished in the Soldier's chibi
fist, at 0.45 m only the head showed, at 0.50 m it read. Give the tool its striking point as a node (`Face`, -Z out
of the face), as a gun carries its `Muzzle`.

- **Approach:** Place a `Muzzle` empty at the barrel tip of every firearm in Blender (-Z out of the barrel in Godot),
  and test that it sits at the barrel end and that the flash spawns on it. **Watch out for:** attachment points belong
  to the model, and the muzzle was a fixed offset from the body, the same for every gun, so the flash sat away from the
  barrel. **Seen:** Deadnight, 2026-11-01 (fix: every firearm carries `Muzzle`, and `test_weapon_muzzle.gd` checks it
  (above)).

## Hands on the weapon {#hands-on-the-weapon}

The kit's clips never move the fingers: every clip holds the same fist, made for the kit's own guns, so copying a kit
hold puts every finger through or off any other weapon (Deadnight measured 8-42 mm into the gun and 20-80 mm off it on
all of its guns, [Deadnight #460](https://github.com/Ryubara/deadnight/issues/460)). Give each weapon its grip from
data instead:

- **Hand sockets in the model**, placed like the `Muzzle`: `Grip` (the right hand's handle, at its centre where the
  middle finger wraps; local +Z up the handle toward the index finger, local +Y the way the straight fingers point,
  which on a pistol grip is along the barrel), `Trigger` (the middle of the trigger's front face) and `Support` (the
  left hand's handle: the fore-end's rear, where a chibi arm reaches, or a vertical foregrip).
- **A solver closes the hand on them** in the hand bone's space, so the grip holds in every clip: lay the socket on
  the line across the knuckles, slide a gun until the trigger is level with the index knuckle, push it to the palm,
  turn it up to 30 degrees about the handle and slide it along the fingers until the index finger reaches the trigger,
  then bend every finger within joint limits to the bend that brings its tip 1 mm from the surface without going in.
  Measure the skinned mesh against the weapon's triangles, inside counted per closed piece (a kitbashed gun is many
  overlapping closed parts, so one parity test over the whole mesh is wrong). Measure the meshes drawn up close only:
  a far level of detail is hidden by its visibility range, not by `visible`, and its decimated hand's longer fingertip
  passed a finger 7 mm off the weapon, and the solver, on the raw model, had curled that finger on the far hand too
  (Deadnight #678, #716).
- **The palm is four bones from the wrist** (`Index1`, `Middle1`, `Pinky1`, `Thumb1`). An IK that turns only the bone
  the weapon rides (`Index1.R`) leaves the other three with the forearm and tears the palm: turn them with it.
- **Check the arm reaches.** A chibi arm is short (the Soldier's is 0.66 m in the game): a solved left-hand grip is
  only right if the IK can put the hand there. Put the support at the fore-end's rear and turn the chest 20-30 degrees
  (left shoulder forward) for two-handed guns; a clamped IK leaves the hand short, inside the stock.
  Put a number on it before placing the `Support`: the shoulder to the support in the game, the grip's distance ahead
  of the shoulder plus the support's ahead of the grip times the size (`|grip_offset.z| + |support.x| x model_scale x
  character scale`), and the grip's distance is set by the stock (the butt lands on the shoulder). Deadnight's Soldier
  held clean at 0.66-0.70 m, stopped 1.7-3.4 cm short at 0.71-0.72 m and put the left hand up to 29 mm into the gun at
  0.85 m, so measure the gap between the hand bone and the IK's target too: on a gun drawn at real length and held 1.3
  times, the support goes about 0.30 ahead of the grip (no closer than the hand clears the magazine) and the butt at
  most about 0.31 behind it, shorter than most real stocks (Deadnight #796).
- **Size against the hand, not only the body.** The kit Soldier's fist is about 2.3 times a real one and his finger 3
  times, on a body at 0.8: the kit draws its guns about 1.33 times real for that (its AK beside the Soldier). Check a
  pistol grip against the three fingers under the trigger finger (about 1.0) and the guard's opening against the
  finger (at least about 0.9) before solving, and scale the weapon, never the hand. Measure after the first build,
  not from the plan: Deadnight's 1911-type pistol, drawn with a chunky grip, measured 1.36 of the fingers at the
  revolver's size factor (1.75), so it is held at 1.5 (grip 1.17, guard 0.96, as the revolver's 1.22 and 0.87;
  [Deadnight #797](https://github.com/Ryubara/deadnight/issues/797)).
- **A model can be held before its weapon exists.** When the model and the weapon that carries it are separate tasks,
  the model's task still proves the hold: a capture builds a hold in code (its class's hold file with the model's
  scene, size, muzzle, butt and support) and gives it to the same builder (Deadnight's
  `tests/captures/model_hold_sheet.gd`), and the grips are solved at the size that hold will have, so the weapon's
  task only points its hold file at the model. Such a model is not in the per-pose grip test (it walks the catalogue
  weapons), so the capture's contact lines are its only check in the game pose: read them, not the solver's table.
  The solver's seat takes the first surface in the palm's line, which a magazine in front of the fore-end can be
  (Deadnight's MP5 left hand sat 17 cm under its hand guard: move `Support` forward clear of the magazine, and
  compare the solved `left_hand` origin with the support point, 12-14 cm under it on a gun that works), and it
  poses the arm unlike the shouldered game pose, so the wrist's skin (`thumb_base`) can go into a stock it measured
  clear (9.1 mm on the M4A1): keep a stock's underside clear of the wrist for about 20 cm behind the grip.
- **Every view of the held weapon uses the same builder.** The night and any screen that shows the soldier with a
  weapon (the menu's stage, a wardrobe, a lobby) put it in the hand through one function (Deadnight's `HeldWeapon`:
  the weapon's own hold, the grip file's place, the arms' IK, the fingers). A view with its own copy keeps the old
  fist the day the grips are solved ([Deadnight #621](https://github.com/Ryubara/deadnight/issues/621)); test it
  by measuring the hands against the weapon on that view with the night's limits.

Deadnight's tools: `build_weapons.py` (`GRIPS`, `TRIGGERS`, `SUPPORTS`), `game/tests/art/solve_grips.gd`,
`HandContact`, `WeaponFit`, and the runtime `HandGripPose`; the design is its `docs/design/animation.md` "Grips".

- **Approach:** Give every held model hand sockets and a solved grip, check grip length, guard opening and reach against
  the hand before solving, and test skin against weapon in every pose (2 mm in, 5 mm off). **Watch out for:** a held
  weapon is a contact of two meshes: the clips never move the fingers, so every weapon got one copied fist; the IK
  turned one of four palm bones and tore the palm; the left arm could not reach the long fore-ends; and the size rule
  ignored a chibi hand 2.3 to 3 times real, so trigger guards were thinner than the finger. **Seen:** Deadnight #460,
  2026-11-02 (fix: the solved grips of this section).
- **Approach:** Build every view of a held weapon with one builder (`HeldWeapon`); when a change touches how a thing is
  held or shown, grep every view of it (menu, wardrobe, lobby, night), give each the night's contact test
  (`HandContact.failures`), and run the suite folder of every view for a new held model. **Watch out for:** the menu
  soldier mounted weapons with its own copy of the hold code, so the per-model grips of Deadnight #507 reached only
  `PlayerAnimation` and the menu kept a fist (the SMG showed the rifle); later three new guns passed the night's grip
  test and floated 0.1 mm past the menu's limit, in a folder not run. **Seen:** Deadnight #621, 2026-11-02; Deadnight
  #793, 2026-11-03 (fix: one builder, the contact test in each view, both grip suites run for a new model).

- **Approach:** Treat the hands on every weapon as a deliverable of their own and refine them hard: each finger closed on
  the `Grip` and `Trigger` sockets, the support hand placed wherever the pose holds the gun with two hands, contact
  measured on the skinned mesh in every clip the weapon plays, and close-ups from the side, the top and the player's
  camera looked at full size, Before and After. **Watch out for:** the 3D Third Person pistol shipped on one fixed
  seat on `hand_r` with the clips' fist (up to 9.5 mm into the grip), the index finger off the trigger and no left hand
  when aiming; its numbers passed and the maintainer's look at the game did not. **Seen:** gdstudio #1001, 2026-11-10
  (fix: the pistol's hold redone to these limits in #1001).

### A weapon in each hand {#a-weapon-in-each-hand}

Test the rig for symmetry before solving a second hand. The kit Soldier is an **exact mirror**: each left bone's rest
rotation is its right one's with `y` and `z` negated (a probe printing both rests per bone: every pair matched to 1e-5,
and in Blender the left hand ended 0.0 m from the right's reflection). So a mirrored pose is the right side's local
quaternions as `(x, -y, -z, w)` (Blender's `(w, x, -y, -z)`), finger poses included, and a weapon on `Index1.L` sits at
the right one's place with `x` turned about (a node whose basis turns the other way draws the model in a mirror; the
`Muzzle` empty keeps its barrel direction). No left grip needs solving: Deadnight's dual pistols reuse the right hand's
grip file mirrored, and the hand contact test measured the left hand within the same 2 mm and 5 mm as the right.

### A real-sized mannequin and the Universal Animation Library {#the-third-person-template-pistol}

<!-- new section: every rule above is for the Toon Shooter Soldier's chibi fist; the 3D Third Person template holds a
real-sized mannequin animated by the Universal Animation Library -->

The 3D Third Person template's pistol (kit #834, `templates/3d-third-person/game/assets/weapons/pistol/`) is
Deadnight's service pistol on Quaternius's mannequin (1.8 m, a real-sized hand), held in the Universal Animation
Library's six pistol clips on the `hand_r` bone.

- **Size it at real length and keep the chunky cross-sections.** Deadnight holds the drawing at 1.95 for its chibi
  Soldier; on the mannequin the drawing at 1.0 (0.25 m overall) puts three fingers on the grip and the index finger
  along the frame to the trigger. Three candidates were seated and captured: real cross-sections (the drawing at
  0.6 across and 0.75 in height) went 5.5 mm at most into the fist but drew the slide 7 px tall at 1080p from the
  camera's 4.4 m, the chunky drawing 9.5 mm and 9 px, and the drawing at 1.3 looked like a toy and went 15 mm in. The
  chunky one matches the kit pistol's cross-section and the clips' fist, which is made for a thick grip.
- **The clips' fist does not hold it: the hands are closed on it by a solved hold** (kit #1001). The clips keep one
  fist in all six pistol clips, and on the seat of kit #834 that fist measured 16 to 18 mm inside the grip and 8 to
  11 mm off it on the two mannequins, with the left hand 8 to 20 mm inside the right one in the aim and shoot clips.
  The rule now: no skin more than 2 mm inside the pistol (or the other hand) and no holding part more than 5 mm off
  it, on the skinned mesh, in every pistol clip and every locomotion clip with the pistol out, on both mannequins.
  The hold that ships measures at most 1.2 mm in on both, and at most 2.7 mm off on the female and 4.4 mm off on the
  male (`tests/gameplay/test_pistol_hold.gd`, which fails on the clips' fist).
- **What the hold is.** `gameplay/weapon/hold/weapon_hold.tscn` (`WeaponHold`) makes three modifiers under the model's
  `Skeleton3D`: the right hand's `HandPose` (three fingers round the grip, the thumb high on the left side, the index
  finger along the frame, and on the trigger as the character aims), a `HoldArm` that reaches the left hand to the
  pistol's `SupportHand` marker while it aims or fires, and the left hand's `HandPose` (fingers over the right hand's,
  thumb forward along the frame). Finger rotations are absolute in each bone's parent, so the grip is the same in
  every clip. Over 40 characters the carried hold costs 5.6 microseconds a character a frame and the aimed one 12.6
  (headless, desktop; `tools/bench/hold_cost.tscn`). It is cosmetic and never sent over a network.
- **The seat needs a wrist turn.** With the barrel on the clips' line a real-sized palm lies flat beside the grip, the
  knuckles 2 cm off the panel. The seat is turned about the grip (24 degrees) and tipped (15), and the hand bone is
  turned back by the same turn (`HandPose.turns`), so the barrel keeps the old line in the forearm in every clip and
  only the wrist bends (28 degrees). That moves the pistol about 10 cm (`Weapon.no_muzzle_offset` follows the muzzle).
- **A closed hand is wider than the clips' open one: hold the arm out while it is carried.** With the grip in the
  palm and the arm hanging as the locomotion clips have it, the grip's foot was 51 to 60 mm inside the female's thigh
  in `Idle` and `Walk`. `WeaponHold.carry_arm_out` lifts the upper arm 8 degrees toward its own side while the pistol
  is carried (the hand moves out, however the elbow is bent) and fades as the character aims; the pistol then clears
  the body by 12 mm or more in every locomotion clip on both mannequins (`tests/gameplay/test_pistol_clearance.gd`).
- **Solve it from Godot's own pose, for both mannequins at once.** `tools/hold/dump_hold_rig.gd` writes the rig as
  Godot plays it, `tools/hold/solve_pistol_hold.py` (numpy and scipy) closes the hands, `tools/hold/write_hold.gd`
  writes the three `HandPose` files and `pistol_held.tscn`: no number of the hold is typed. The two mannequins share
  the skeleton from the hands down, but their skins differ by up to 3.3 mm in the same pose (in both directions), so
  the solver measures both skins in every step and presses the nearer one 0.8 mm into the surface; the other is then
  up to 2.5 mm off it. A hold solved on one mannequin put the other 2.7 mm into the grip.
- **The left hand follows the reload** (kit #1031). `Pistol_Reload` (1.67 s, stretched to the weapon's
  `reload_time`) has the left hand on the gun for its first 4 hundredths, down at the left hip for the new magazine at
  a quarter, under the grip from 0.54 to 0.71 and back on the gun from 0.88. After the solved seat moved the pistol
  about 10 cm in the hand, the clip's own left hand was 16 to 22 mm inside the gun or the right hand for a third of the
  clip on the female and 20 to 23 mm at its ends on the male, and under the grip it stood beside the gun's right side,
  not under the magazine. `WeaponHold` now takes the hand through the clip's steps by the clip's own time
  (`CharacterAnimation.reload_progress()`: how much of the body the one-shot holds, and the share played): on the
  `SupportHand` marker, opened and let go to the clip's arm (0.04 to 0.10), brought to the line under the magazine
  (0.30 to 0.40) one magazine's length down the grip, pushed up it (0.40 to 0.54) to the `MagazineHand` marker, where
  the heel of the palm is on the magazine's base as a real reload seats one, then down, round the grip's foot and
  onto the gun (0.71 to 0.88). Where the hand holds, it is within the 2 mm and 5 mm (the palm 1.6 to 3.1 mm off the
  base, nothing more than 1.2 mm in); while it moves, a fingertip passes 4 to 5 mm through the other hand for a
  hundredth of the clip in three places (0.03, 0.05, 0.79), which the test caps at 6 mm. The trigger finger is off
  the trigger for the whole reload. Where the hand should be at each moment was decided from the clip and from how a
  reload is taught: the magazine is fetched at the belt, guided in and seated firmly with the support palm, and the
  grip is taken again ([Shooting Illustrated](https://www.shootingillustrated.com/articles/2012/10/25/semi-automatic-handgun-reloading),
  [AmmoLand](https://www.ammoland.com/2023/03/4-pistol-reload-methods-9-magazine-tips)). The clip has no rack of the
  slide and no magazine in the hand, and the pistol's `Magazine` node does not move yet.
- **Search order.** The seat first (the palm brought to the surface along the pistol's own Z, then a coordinate
  search over its place and turn, scored by the closed fingers and a thumb root high under the tang), then each finger
  on a grid of joint angles followed by a local search (contact of its three parts, no more than the allowed depth, and
  a natural curl), then the left hand as the right one mirrored across the pistol and moved, its fingers closed on the
  pistol and the right hand together.

The template's rifle (kit #886, `templates/3d-third-person/game/assets/weapons/rifle/`) is Deadnight's M4A1 at the
real 0.82 m on the same mannequin. The library has no rifle clip, so the rifle's hold is built from IK:

- **The pistol's seat gives both hands.** The right fist's place on the pistol's `Grip` (the seat times the socket,
  inverted) moved onto the rifle's `Grip` is the right hand's target, and mirrored across the body's middle plane
  (`Basis` M B M and M o, with M = diag(-1, 1, 1)) onto `Support` it is the left hand's. The mannequin's rig is an exact
  mirror (left rests equal the reflected right ones to 1e-6 m and 0.04 degrees), as the Toon Shooter Soldier's
  ([A weapon in each hand](#a-weapon-in-each-hand)).
- **The hold is engine nodes on the skeleton:** a chest turn over the three spine bones (a short
  `SkeletonModifier3D`), a `TwoBoneIK3D` per arm toward a `Marker3D` on the rifle with a pole marker, and a
  `CopyTransformModifier3D` per hand that copies the target's rotation (Godot 4.7). The rifle hangs on a node in the
  model's space with `Butt` in the right shoulder's pocket; aiming turns that node about the pocket. Over 40
  characters the modifiers cost about 8 microseconds each on the desktop.
- **Read the pose in `skeleton_updated`.** `get_bone_global_pose()` gives the modifiers' result only inside the
  skeleton's `skeleton_updated` signal; outside it a probe read the clip's pose and reported a solved hand 19 cm off its
  target. A `BoneAttachment3D` moves in the same signal, maybe after your listener: copy the bone poses in the signal
  and read the attachment's transform afterwards (kit #1001). A skeleton with no modifier that dirties it (the
  mannequin carries an inactive `PhysicalBoneSimulator3D`)
  never emits it, so a probe that awaits the signal there waits forever.
- The study that measures five holds and renders them is the template's `tools/capture/rifle_hold_study.tscn`; the
  proposal and its numbers are in the rifle folder's README.
- **The hold in the game (kit #889)** is not that study's: `TwoHandHold` places the gun from the chest bone, reaches
  each arm with a `HoldArm` and closes the fingers with poses solved on the rifle's own `Grip`, `Trigger` and
  `Support`, as the pistol's are. How it is built, its numbers and what went wrong on the way:
  [The rifle in both hands](../../engines/godot/third-person/shooting.md#rifle-hands).

- **Approach:** Measure the left arm's reach to the `Support` in the pose the game will hold before keeping a support
  copied from another rig's model: shoulder to the hand's target against the arm's length, with the chest turn the hold
  will use. **Watch out for:** Deadnight's support (0.29 m ahead of the grip, for a chibi Soldier holding the gun 1.3
  times) left the female mannequin's 0.49 m arm 4 cm short with the chest turned 30 degrees and 13 cm short without, and
  the pistol clip's arms keep the target 0.72 m from the shoulder even with the support moved (22.5 cm short). **Seen:**
  gdstudio #886, 2026-11-10 (fix: the support moved 4 cm back, 0.25 m ahead of the grip; both hands then reached in
  every hold of the study).

- **Approach:** Measure a hold made by modifiers inside the skeleton's `skeleton_updated` (after the modifiers, before
  the next frame), and free the character only after an `await process_frame` that leaves the signal. **Watch out
  for:** `get_bone_global_pose()` read in `_process` gave the clip's arm hanging at the hip, so a close-up camera
  placed from the hand framed the thigh (place it from the hand's IK target instead); and freeing the player right
  after `await skeleton.skeleton_updated` freed the skeleton during its own signal and crashed Godot (signal 11).
  **Seen:** gdstudio #889, 2026-11-10 (`rifle_tour.gd` and the rifle's contact probe).

- **Approach:** Measure a hold against the pose Godot plays: write the bones and the hand skinned on the CPU (weight
  times `get_bone_global_pose(bone) * skin.get_bind_pose(bind)` times the vertex) from Godot, read them into Blender
  with (x, y, z) to (x, -z, y), search the seat there, then capture it in Godot. **Watch out for:** the clip assigned in
  Blender to the mannequin's armature put the hand 2 to 3 cm off Godot's with the index finger straight, though the
  rests match, and a seat aligned to that finger turned the barrel 60 degrees out; headless,
  `bake_mesh_from_current_skeleton_pose()` fails (no skin registered with the skeleton). **Seen:** gdstudio #834,
  2026-11-08 (fix: the Godot dump; its seat held in all six clips).

- **Approach:** Reach a hand to a point that rides the same skeleton (the support hand on a weapon the other hand
  carries) in a `SkeletonModifier3D` of your own that works the target out from the bone's pose in that update (the
  template's `HoldArm`), and prove it on the live player while it walks and fires. **Watch out for:** the engine's
  `TwoBoneIK3D` aimed at a node used the place the node had before the skeleton's update, whether the target sat under
  the `BoneAttachment3D` or was moved by a modifier: the hand trailed the pistol by 35 mm in the shoot clip and by
  52 cm after a jump of the pose; a modifier just switched on also needs a second update before a test reads it.
  **Seen:** gdstudio #1001, 2026-11-10 (fix: `HoldArm`, 0.0 mm from the marker in every sample).
- **Approach:** Count a point as inside a hand or a weapon by crossings of a ray per closed piece (the mannequin's hand
  is 29 pieces: a capsule a finger bone, a ball a joint, and a palm open at the wrist, so three rays vote), in the test
  and in the solver alike, and check one disputed number against a third measure on a dump of the posed meshes.
  **Watch out for:** the side of the nearest triangle's normal read a thumb lying beside the other thumb as 5.3 mm
  inside it when it was 1.6 mm, and a hand 30 mm inside the other from far away; the solver, which smoothed the same
  rule over a grid, said 1.1 mm, so the two disagreed and the solve chased the test. **Seen:** gdstudio #1001,
  2026-11-10 (fix: `HandContact` and `hold_field.py` count per piece; they agree to 0.4 mm).
- **Approach:** Make the solver's distance grid cover the whole weapon and a hand's thickness round it, and make a
  point outside the grid read the value at the grid's edge plus the way there. **Watch out for:** a grid that stopped
  at 13 cm ahead of the grip on a pistol whose muzzle is at 20.7 cm, with 5 cm returned outside it: the index finger
  along the frame reached past the grid, the solver saw nothing there and laid it 2.8 mm into the dust cover.
  **Seen:** gdstudio #1001, 2026-11-10 (fix: the grid's bounds are the pistol's own; the finger lies 0.7 mm off).
- **Approach:** Give a finger solver a cost for a natural curl (the last joint follows the middle one, every joint
  near a closed grip's) and a thumb a cost for a hooked tip, sample a triangle along each of its edges when building a
  distance grid, and keep a margin on the depth limit in any search that measures only every third vertex.
  **Watch out for:** contact alone gave straight fingers with a hooked tip and a thumb bent 84 degrees at the tip;
  sampling by a triangle's longest edge made millions of samples on long thin triangles and the grid never finished;
  a search on every third vertex chose a left hand whose full measure was 0.4 mm too deep, and the final solve then
  curled the index finger into a fist to escape. **Seen:** gdstudio #1001, 2026-11-10.
- **Approach:** Take a hand through a clip that moves it on and off the weapon by the clip's own time: a marker and a
  solved finger pose for each place it holds, a straight way in along the line the part travels (a magazine goes up
  the grip) and a way out that backs off before it crosses. Measure every hundredth of the clip once and keep the
  deepest shares in the test. **Watch out for:** the clip's place for the hand fits only the seat the clip was made
  with (after the reseat it was beside the gun, not under the magazine); a straight blend from under the magazine to
  the support place went 21 mm through the grip's foot; fingers opened toward their rest went 4 to 5 mm into the
  trigger guard and the other hand; a test at every 4 hundredths passed while three shares between were 4 to 5 mm in.
  **Seen:** gdstudio #1031, 2026-11-10 (three passing moments of 4 to 5 mm are left, capped at 6 mm).
- **Approach:** Seat a hand on a surface by its palm with the fingers already closed, and close the fingers again
  after each seating, a fixed number of times; hold a part that the game's test reads deeper than the solver (the
  male thumb's root, 1.4 mm) off the surface in the solver. **Watch out for:** the palm's skin near the knuckles
  follows the fingers, so a palm seated with open fingers ended 4 to 6 mm in or 9 to 13 mm off once they closed;
  seating on the skin the hand bone alone moves pushed the hand 17 mm into the gun; backing the whole hand off until
  nothing was deeper than 0.3 mm took it 8 mm off for a thumb that touched sideways; a bisection of the push over
  the whole way failed, since past the gun the palm is clear again (step to the first touch, then bisect).
  **Seen:** gdstudio #1031, 2026-11-10.
- **Approach:** After closing a hand on a grip, measure the weapon against the body in the locomotion clips again, and
  bench a change of modifiers one configuration a process. **Watch out for:** the seat that put the grip in the palm
  moved the pistol 6 cm toward the body, into the thigh in `Idle` and `Walk`, which only the clearance test showed
  (from the right side the capture looked fine); a second set of 40 mannequins in one process measured ten times the
  first with nothing changed, which read as a hold that cost 5 ms a character. **Seen:** gdstudio #1001, 2026-11-10
  (fix: `carry_arm_out`; `hold_cost.tscn` takes the run as its argument).

## Moving parts and a reload's ammunition {#moving-parts-and-a-reloads-ammunition}

A reload reads when something on the gun moves (a drum comes off, the barrels break open, a cylinder swings out, a
lever is thrown) and the left hand brings something back from the belt. Both are the modeller's, like the `Muzzle`:

- **The moving part is its own node**, built on its own and joined at its pivot (the hinge pin, the crane, the lever's
  pin, a drum's centre), parented to the weapon's root so the weapon keeps its origin. The game turns it about an axis
  of the model or slides it, and nothing else needs to change: the grip sockets, the `Muzzle` and the triangle count
  stay the same (Deadnight #683 split five guns this way and every count and size came out identical). Move with the
  part what moves in the real gun: a break-open's forend goes with its barrels, a lever rifle's trigger stays.
- **The ammunition is a small model of its own** beside the gun's (`<gun>_ammo.glb`: two shells, a round, a
  speedloader, a flare cartridge), never a hidden node in the gun's file, which every other view of the gun (a wall buy,
  a prize, the menu) would then show. A drum that is the gun's own part is the same mesh again.
- **Draw the ammunition for the fist, not the gun.** At the gun's size a shell vanished inside the Soldier's left
  hand; the game holds it at 1.5 times the gun's size, standing out of the fingertips (the hand bone's +Y runs along the
  fingers, their tips 0.25 bone units out), as the grenade showed: it passed every hold test and was hidden in the
  fist from the side, so a small held prop gets close views of its own in the capture sheet (Deadnight #285).
- Godot's axes for a gun drawn along Blender -X: the muzzle is -X, up +Y and **the gun's left is +Z** (Blender -Y). A
  break-open's muzzle drops with a positive turn about +Z; a cylinder swings out to the left with a positive turn about
  +X about a crane under its left side.

Deadnight's tools: `build_weapons.py` (`NODES`, `AMMO`); the motion is its `docs/design/animation.md` "Reloading".

## Building by script {#building-by-script}

| Lesson | Detail |
| --- | --- |
| Draw real, then fatten | Drawn at real proportions, a gun looks spindly beside the kit. Scale every part 1.4-1.5x across its length before chamfering to get the kit's chunky cross-sections |
| Big receiver, shallow stock | The kit's guns read as a large grey block; keep the stock shallow with a slanted butt, or the fattening turns it into a wedge (Deadnight's PPSh, MP5 and M4A1 first came out with butts 0.16-0.20 m deep in drawing units and read as wedges; 0.14-0.16 m read). Render a turntable beside a kit-style gun after the first build, before solving anything against it |
| Chamfer only the big parts | A one-segment chamfer (about 17 mm at kit scale) costs a box 44 tris instead of 12; leave screws, pins, sights and lever segments hard |
| Kitbash, never weld | Separate closed parts; levers and guards are overlapping boxes along a path |
| Round parts by lathe | One turned profile with the chamfers in it; flat shading keeps the kit's facets |
| Turn along the barrel | A tank lying on a gun, a nozzle or a bezel turns about X, not Z; a profile closed into a loop turns into a ring with a hole (a lens set inside a bezel, a nozzle with a glowing disc deep in it), where a capped cylinder would hide what is inside (Deadnight's `weapon_specs/_revolve.py`) |
| Far level from the same description | No chamfers, half the sides on round parts, small parts left out: 22-32 % of the held count. A turned part with rounded ends gets a far profile of its own: keeping every other point made a tank's two ends unlike. Look at the far level in a turntable beside the near one |
| One material per family | A small palette atlas, every face's UVs collapsed on its colour swatch, roughness 0.415, metallic 0.4 |
| Compare rebuilds by geometry | The glTF export's triangle order changes from run to run, so a rebuilt file never matches the old one byte for byte: compare nodes, vertex buffers and the triangle set, and commit only the files the change is for |
| Look at it | A turntable sheet beside two kit weapons at the same scale shows what numbers miss: the first pass had the right lengths and triangle counts, and still read thin |
| Chamfers cost on round parts | A 12-sided cylinder is 44 triangles bare and 92 chamfered, a box 12 and 44: chamfer the big parts that face the camera and leave collars, rings and small blocks bare; count on the first build ([Build scripts](build-scripts.md#checks)) |
| Trim is a band, not a cap | A rim drawn as a slightly larger capped cylinder covers the face it trims; draw it as a band round the edge, then read the cells by area |
| A copied guard needs its frame | A trigger guard copied from another gun keeps its opening only if the frame above the trigger sits at the donor's height: 5-7 mm lower took Deadnight's MP5 and M4A1 from 0.95 to 0.83-0.86 of the finger; measure the fit after the first build |

## Palette cells in Godot {#palette-cells-in-godot}

Every face's UVs sit on the centre of one swatch of a G x G palette, so a shader or an emission texture can tell the
parts apart by colour cell with no extra texture. In Godot (the glTF flips V) **a face's cell is
`floor(UV.x * G) + G * floor(UV.y * G)`**, cell 0 the top-left swatch; in Blender it is
`floor(u * G) + G * floor((1 - v) * G)`. Check the formula on one known swatch: read the mesh's UVs in Godot and
sample the palette there (Deadnight #786 did it for its 4 x 4 weapon palette; a row taken from Blender's bottom-up
V lit nothing).
A swatch that must glow (an energy cell, a lamp) gets its own cell and is lit by an emission texture of the atlas's
layout, black but for that cell, on a copy of the material: no second material, no extra draw call. Append new
swatches at the end of the palette's list, so no older swatch moves and no model has to be rebuilt.

## What reads on a phone {#what-reads-on-a-phone}

From a shoulder camera in the aim pose every gun is a fist and a barrel tip: a weapon is recognised from the side,
at the hip, reloading and in other players' hands. A weapon is drawn at about `screen height / (2 d tan(fov / 2))`
pixels a metre; for a 60 degree vertical field of view and a landscape phone 390 logical pixels tall that is 130 px/m
for the player's own weapon (2.6 m away) and 42 px/m for a teammate 8 m away. Render the set flat black at those sizes
and look:

- At 42 px/m a pixel is 2.4 cm: trigger guards, lever loops, sights and screws vanish; drums, magazines, grips and
  barrel blocks stay. Deadnight's lever rifle and double shotgun were one shape there, and its revolver and flare gun
  differed only by colour.
- So give each weapon **one signature mass at least about 7 cm across in the game** (3 px at 42 px/m) that changes its
  side outline, make no two weapons of one class share an outline, give a colour mass of its own where outlines are
  close, and never put a weapon's identity in a part the far level drops.
- **A sleeve round a tube is not a mass.** Deadnight's pump shotgun (#796) first had its pump drawn just round the
  magazine tube, 6.4 cm deep in the drawing: at 42 px/m it was a bar and a stock, the double shotgun's outline. Deepened
  to 8.8 cm (8.8 x 1.3 x 0.8 = 9 cm in the game) it hangs below the tube as a block with a gap of bare tube behind it,
  and the outline is its own. A moving part that is the signature (a pump, a feed cover, a box) is drawn to the mass
  rule, not to the real part's size.

Deadnight's `tools/blender/render_weapon_plan.py --silhouette --px-per-m 42` draws it; the measured set is its
`docs/research/weapon-models.md`.

## Many weapons in parallel {#many-weapons-in-parallel}

When several agents build weapons at once, give each weapon its own module (Deadnight's
`tools/blender/weapon_specs/<id>.py`: its builders and one `SPEC` dict with the node pivots, sockets and ammunition,
loaded by the one build script) instead of entries in the build script's shared tables, and settle what they must
agree on before they start: the palette's new cells (added once, by the planner), the size rule, the budgets, each
weapon's signature and class. The game-side lists of models (tests, the grip solver) still take a line each: add yours
on a line of its own and merge main before pushing.

**A model before its hold.** The model batches land before the build issue adds the weapon to the catalogue and
writes its hold file, but the model still has to be seen in the hands. Film it through the night's own builder with a
hold made in the capture (Deadnight's `game/tests/captures/model_hands_sheet.gd`: a `WeaponHold` built from the plan's
numbers, handed to `PlayerAnimation` the way `equip` does, beside catalogue weapons equipped the normal way), never a
copy of the hold code. Solve the grip at the size the hold will use: the grip test compares each grip's `model_scale`
with its weapon's hold, so a hold written later at another size needs the grip solved again; say the size in the pull
request. A plan render that reads the sizes from the hold files takes the new models with their size given
(`render_weapon_plan.py --add id=row@model_scale`). Two parallel batches each wrote that capture and that flag under
the same names (Deadnight #816 and #818): before writing a tool a batch needs, look in the open pull requests of the
other batches for one.

## Budgets {#budgets}

Kit guns are 1.0-1.45k tris and melee 660-760. For a third-person web game, one held and world model at 1.5k and a far
level at 500 is enough. Deadnight's first ten came out at 432-1,172 tris and 108-374 for the far level (24-50 %
of the near count).
