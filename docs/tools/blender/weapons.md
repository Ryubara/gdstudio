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

Moved to [Attachment points](weapon-models/building.md#attachment-points).

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

- **Approach:** Lay the second hand over the first as the grip is taught, never beside it: research the grip finger
  by finger, solve the two hands against each other and measure each against the other
  ([The two-handed pistol grip](weapon-hands/two-handed-pistol-grip.md)). **Watch out for:** on the 3D Third Person
  pistol each hand met its own limits and the two sat side by side, the support hand uncanted and its thumb over the
  trigger guard's opening. **Seen:** gdstudio #1084, 2026-11-11 (maintainer correction; fix: the hold rebuilt, cant 43
  degrees).
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
Library's six pistol clips on the `hand_r` bone. Since kit #1187 the template's characters wear GDStudio's prototype
bodies (`form_female.glb`, `form_male.glb`, [the bodies](../../engines/godot/third-person/character.md#mannequins)),
whose hands are a person's size (0.181 m and 0.195 m wrist to fingertip, against the library rig's 0.232 m): the
hold below is solved on each of them, one body at a time, and the numbers in this section from before that were
measured on the Quaternius pair.

The two mannequins' skins differ at the fingertips: the female's are weighted up to half to the fingertip leaf bones
(`index_04_leaf_r` and its like), the male's are not. A hold solver or a contact test that moves or sorts the skin by
a finger's three bones leaves those vertices where the last pose had them (up to 28 mm off), so count the leaf with
the finger's last bone. The fix and its entry come with the rifle's hands (kit #889 and #1040, on 3D Third Person's
shooting page once that work lands).

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
  The hold that ships measures at most 1.6 mm in on both, and at most 2.7 mm off on the female and 4.4 mm off on the
  male (`tests/gameplay/test_pistol_hold.gd`, which fails on the clips' fist).
- **What the hold is.** `gameplay/weapon/hold/weapon_hold.tscn` (`WeaponHold`) makes three modifiers under the model's
  `Skeleton3D`: the right hand's `HandPose` (three fingers round the grip, the thumb high on the left side, the index
  finger along the frame, and on the trigger as the character aims), a `HoldArm` that reaches the left hand to the
  pistol's `SupportHand` marker while it aims or fires, and the left hand's `HandPose` (canted, its fingers over the
  right hand's and round the grip's front, the index finger under the trigger guard, the thumb forward along the
  frame; the right thumb then lies on its root). Finger rotations are absolute in each bone's parent, so the grip is
  the same in
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
- **One hold a body** (kit #1187). Two hands of different sizes do not share a pose: the solver takes `--body=female`
  or `--body=male` (`--body=both` is the old measure of two bodies whose skeletons match from the hands down), and
  `write_hold.gd -- <hold.json> <body>` writes the female's into the files above and any other body's into one
  `HoldFit` (`gameplay/weapon/hold/pistol_fit_male.tres`: seat, both markers, `support_way` and the eight poses, the
  trigger finger's way, the lifted thumb of the two-handed grip and its way among them)
  that `WeaponHold.fits` lists and puts on when the model is that body's file. A smaller hand changes more than
  the finger angles, on every gun: its straight index finger ends nearer the trigger, its thumb reaches other
  surfaces, and the place of the whole hand that suited a larger one can leave the palm off the grip (the rifle's
  did: [the rifle in both hands](../../engines/godot/third-person/weapon-pickups.md#rifle-hands)), so look at each
  body's close-ups again and do not stop at the contact numbers. The left hand is solved over the right
  index finger on the trigger and along the frame at once (a reload takes the finger off the trigger while the left
  hand still holds), the finger along the frame is kept 20 mm from the trigger, and the cupped fingers under the
  magazine are measured along the magazine's line too, which they ride up and down. On the two bodies: right hand at
  most 1.2 mm in, holding parts at most 1.0 mm off in the solver; the whole hold suite passes for both
  (`tests/gameplay/test_pistol_hold.gd`).
- **The two hands hold it together, and the left hand follows the reload** (kit #1084, #1031, #1051, #1078, #1079).
  The left hand is laid over the right one as a two-handed grip is taught, goes on and off the gun one way, and the
  trigger finger has a solved way to the trigger: [The two-handed pistol grip](weapon-hands/two-handed-pistol-grip.md).
- **The slide is racked by a clip of our own** (kit #1081, `assets/animation/pistol/`). `Pistol_Rack` (0.93 s, 28
  frames) is an overhand rack: the left hand over the top of the slide just in front of the rear sight, the palm on
  the top, four fingers down the right side with the index finger's pad on the serrations and the thumb's pad on the
  left side's; it pulls the slide back 4.5 cm while the right hand pushes the frame 3 cm forward, lets go at the rear
  and follows through. Overhand, not the slingshot pinch, because the third-person camera sits behind and above the
  right shoulder: a pinch at the slide's rear is hidden between the pistol and the chest, a hand over the slide and
  an elbow that swings back are a silhouette. The pistol stays in front of the right shoulder (at the body's middle
  line the shoulder hides it from the camera), 16 cm in from the aim pose, canted 36 degrees and turned 15, which is
  what the left wrist needs on `form_female` (35 degrees of bend; 11.5 cm, 28 and 10, the Quaternius body's
  numbers, bent it 53 to 57). The clip starts and ends on the last frame of `Pistol_Reload` (the same as its first)
  and is keyed on the player's body. **Each body has its own hand on the slide** (`solve_rack_hand.py
  --body=female|male`, as the hold is solved a body): `build_pistol_rack.py` writes one `SlideRack` a body
  (`pistol_slide_rack.tres` lists the male's in `fits`; `SlideRack.fit()` chooses by the model's file) with the
  hand bone's place in the pistol's space on every frame it is near the slide, the fingers closed on the slide and
  opened over it, the slide's travel and the beats. What plays the clip reaches the left hand there with a `HoldArm`,
  puts the fingers on with a `HandPoseModifier` (`SlideRack.set_fingers()`) and moves the `Slide` node. Measured on
  every frame on both bodies: the right hand 1.2 mm in and 1.0 mm off at most, the left hand on the slide 1.0 mm in
  with the palm and every fingertip on the surface, 0.0 mm from its place, at most 2.3 mm in on its way at any half
  frame with the pistol carried and 4.4 mm with the pistol where the clip has it, and no limb more than 4.5 mm in
  another where the rack moves the hand. Before the per-body solve (the Quaternius hands' place and curls on these
  bodies) the palms were 12.3 to 13.9 mm off the slide and the index fingertips 13.1 to 18.9 mm inside it.
- **Search order.** The seat first (the palm brought to the surface along the pistol's own Z, then a coordinate
  search over its place and turn, scored by the closed fingers and a thumb root high under the tang), then each finger
  on a grid of joint angles followed by a local search (contact of its three parts, no more than the allowed depth, and
  a natural curl), then the left hand from the right one mirrored across the pistol, moved and canted, its fingers
  closed over the right hand's, then the right thumb on the left one's root, each hand measured against the other
  ([The two-handed pistol grip](weapon-hands/two-handed-pistol-grip.md#solving-two-hands)).

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
  [The rifle in both hands](../../engines/godot/third-person/weapon-pickups.md#rifle-hands).

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
  **Seen:** gdstudio #1031, 2026-11-10 (three passing moments were left; fixed in #1051).
- **Approach:** Give a hand one way on and off the weapon: the fingers open where it holds, the opened hand leaves
  along a line solved clear for both skins, and only at the line's far end does the clip's arm take over. Hold it as
  one number (how far on the weapon) that the aim and the reload blend. **Watch out for:** fading the arm's weight
  from the hand's place let the clip pick the line out (the little finger went 5 mm through the grip); a plan that
  blended the arm and the way apart gave a half-open hand to the clip from its place when the reload was shorter
  than its fade-in; a finger that lies flat on a panel cannot open in place (its tip turns into the panel), so it
  tucks or waits for the line. **Seen:** gdstudio #1051, 2026-11-10 (1.2 mm at most on both mannequins).
- **Approach:** Scan a moving hand finer than the test will measure it (a quarter of a hundredth of the clip) and on
  the live character on every update, not only on a posed stage. **Watch out for:** the scan at every hundredth
  read 3.9 mm where a quarter-hundredth beside it read 9.1 mm; the posed stage showed nothing of an arm 6 to 16 cm
  short of the gun while the aim comes up, nor of the trigger finger crossing the left thumb as the reload fades.
  **Seen:** gdstudio #1051, 2026-11-10 (the two live faults are #1078 and #1079).
- **Approach:** Measure a batch of poses a few hundred at a time when every pose is measured at every step on
  every vertex, and thin the grid before adding steps. **Watch out for:** the little finger's 12,000 candidate
  poses at 16 blend steps on 500 vertices asked for gigabytes at once and the solve ran ten minutes; in batches of
  400 on a grid a third the size it gave the same pose in under five. **Seen:** gdstudio #1051, 2026-11-10.
- **Approach:** Give a clip that puts a hand on a weapon the other hand carries the hand's whole way near the weapon
  as data in the weapon's space (a place a frame, from before it touches to after it has let go), reach the hand
  there in the game, and pose every measured body that way in the build. **Watch out for:** rotations keyed on one
  mannequin left the other's hand 7 to 9 cm from the slide, and the hold moves the pistol after the clip on both
  (the carried arm's swing: 6.7 cm); a reach weighted in only while the hand gripped took the male's hand 17.8 mm
  through the gun as it closed and let go; beats on half frames put the place 2 mm off between two samples.
  **Seen:** gdstudio #1081, 2026-11-11 (fix: `SlideRack.places`, the reach on from over the slide to the end of
  the follow-through, the beats on whole frames).
- **Approach:** Before keying a two-handed move, put a number on the wrist: the angle between the forearm and the
  hand's own line with the arm solved, on every frame; bring the weapon toward the body and cant it until the
  forearm can lie along the hand. **Watch out for:** with the pistol at the aim pose's distance the left arm is
  nearly straight, so the forearm points forward while a hand over the slide points across it: the wrist bent 80
  degrees. 12 cm closer and canted 28 degrees it bends 26. **Seen:** gdstudio #1081, 2026-11-11.
- **Approach:** Take a hand off a grip sideways, round the weapon, with its fingers as they let go, and measure the
  two hands against each other both ways (`limb_overlap.py` does; `HandContact.measure("l", true)` measures only
  the left hand's points in the right hand). **Watch out for:** lifted straight from the support grip to the top of
  the slide, the left index finger went through the trigger guard and the right middle finger: 7.5 mm by the limb
  check while the hand measure read 0. The limb check also reads touching hands 3 to 4 mm deeper than the hand
  measure (4.7 mm for the support grip the hold's test reads as 1.2 mm), so its 5 mm limit is not the hold's 2 mm.
  **Seen:** gdstudio #1081, 2026-11-11 (fix: the way out goes 9 cm to the gun's left first, then over the top).
- **Approach:** Carry a gripping hand with the part it grips by the part's own travel (its place on the closed slide
  plus what the slide has moved), and measure every half frame. **Watch out for:** places on whole frames are a
  straight line between two of them while the slide eases, so the fingers slid 2.3 to 2.8 mm along the serrations at
  the half frames, past the 2 mm the whole frames passed. **Seen:** gdstudio #1081 (PR #1103), 2026-11-11
  (`SlideRack.hand_place`).
- **Approach:** Solve a hand that works on a weapon once for every body, like the hold, and give the clip a per-body
  resource (the hand's place and way, the fingers closed and opened) chosen by the model's file; key the clip on the
  player's body and put the other bodies' arm and fingers on over it. **Watch out for:** a place and curls solved on
  the Quaternius hands (0.232 m) left the prototype bodies' palms (0.181 and 0.195 m) 12 to 14 mm off the slide and
  the fingertips 13 to 19 mm inside it, and the clip's own arm, keyed on the old skeleton, 74.7 mm from the slide.
  **Seen:** gdstudio #1081 (PR #1103), 2026-11-11 (fix: `--body`, `SlideRack.fits`, `set_fingers()`).
- **Approach:** Give a search for a hand's place the arm behind it (the forearm's line and the shoulder in the
  weapon's space, from the build) and take a searched place only after the build's wrist and reach numbers agree.
  **Watch out for:** scored by contact alone, the search walked the wrist 11 cm up the barrel with the fingers
  turned back to the serrations: the wrist bent 43 degrees and the male's arm stopped 8 to 10 mm short in Godot. The
  body moves the wrist too: one pistol place bent the Quaternius female's 26 degrees and `form_female`'s 53 to 57.
  **Seen:** gdstudio #1081 (PR #1103), 2026-11-11 (fix: the pistol brought in and turned, the places fixed in
  `PLACES`; the search's arm cost did not hold the turn).
- **Approach:** Solve the opened hand, do not blend it: each finger the pose nearest its grip whose outer two parts
  are clear where the hand lies, clear down the straight line it arrives by, and within the limit at every blend back
  to the grip; and measure the gripping hand along the part's travel against what stays behind. **Watch out for:**
  an opened hand blended from the rest pose pointed its thumb into the slide (5 to 12.5 mm through the top's edge
  as the hand came down); asking a finger's first part to lift made the fingers splay; a hand solved on the closed
  slide was 3.9 mm into the hammer with the slide back. **Seen:** gdstudio #1081 (PR #1103), 2026-11-11.
- **Approach:** Measure a clip's hands with the weapon in each place the game can have it (carried with the arm
  held out, and where the clip has it), and leave the hold's own support-grip frames out of the build's limb limit.
  **Watch out for:** the stage carried the pistol 7 cm from where the clip's arm expects it, so the test read 0 mm
  on the way off the grip while the build read the female's fingers 5.5 to 6.3 mm in the right hand; the hold's
  contact (7.8 mm by the limb check, 1.1 mm by the hold's) hid that behind the deepest number. **Seen:** gdstudio
  #1081 (PR #1103), 2026-11-11 (fix: the hand leaves along the hold's `support_way`; the arm-in test).
- **Approach:** After changing an imported file in a kept game, check the import ran (the time of the file under
  `.godot/imported/`), write the import's output to a file, and copy files one by one. **Watch out for:**
  `godot --import | grep | head -20` ends Godot at the twentieth warning, and `cp folder/*` meeting a `__pycache__`
  under `set -e` ends the script before the import: for six rounds new rack data was measured on the old clip (the
  hand 8 to 17 mm from its place, which read as a short arm). **Seen:** gdstudio #1081 (PR #1103), 2026-11-11.
- **Approach:** Film a two-handed grip from the side the body hides too (the gun's left: a camera behind and above
  it, the near plane past the chest) and read the thumb there. **Watch out for:** five views showed the fingers and
  never the thumb; its tip was on the surface while it hooked under the slide and back, bent 57 and 45 degrees.
  **Seen:** gdstudio #1081 (PR #1103), 2026-11-11 (the `left` view; a cost for straight joints laid it flat).
- **Approach:** In a capture that moves one camera through several views of a pose, take the first view after a new
  pose twice and keep the second. **Watch out for:** the first picture after each pose still showed the camera of
  the picture before it (three awaited `frame_post_draw` did not help), which read as a view blocked by the body.
  **Seen:** gdstudio #1081, 2026-11-11 (`tools/capture/rack_closeups.gd`).
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

Moved to [Moving parts and a reload's ammunition](weapon-models/building.md#moving-parts-and-a-reloads-ammunition).

## Building by script {#building-by-script}

Moved to [Building by script](weapon-models/building.md#building-by-script).

## Palette cells in Godot {#palette-cells-in-godot}

Moved to [Palette cells in Godot](weapon-models/building.md#palette-cells-in-godot).

## What reads on a phone {#what-reads-on-a-phone}

Moved to [What reads on a phone](weapon-models/building.md#what-reads-on-a-phone).

## Many weapons in parallel {#many-weapons-in-parallel}

Moved to [Many weapons in parallel](weapon-models/building.md#many-weapons-in-parallel).

## Budgets {#budgets}

Moved to [Budgets](weapon-models/building.md#budgets).
