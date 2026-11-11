# The two-handed pistol grip

<!-- new section: nothing said how two hands hold a pistol together; the 3D Third Person pistol's hands each met
     their own targets and sat beside each other (gdstudio #1084) -->

How a pistol is held in two hands as it is taught today (the thumbs-forward grip), what each finger does, and how the
3D Third Person template's pistol hold was rebuilt to it (kit #1084). The rules every held model meets are on
[Weapons: hands on the weapon](../weapons.md#hands-on-the-weapon); the hold's parts in the game are on
[Weapons: the template's pistol](../weapons.md#the-third-person-template-pistol).

## How the grip is formed {#how-the-grip-is-formed}

<!-- new section: the research the rebuilt hold follows, finger by finger, with its sources (gdstudio #1084) -->

A hold solved one hand at a time puts the second hand where the first leaves room, beside it. A real grip is built the
other way round: the support hand is laid **over** the shooting hand, and every part of it has a place that the
shooting hand makes for it.

| Part | What it does | Source |
| --- | --- | --- |
| Shooting hand, web | High on the backstrap, under the tang; a hand set too low is the most common fault | [American Rifleman][ar] |
| Shooting hand, three fingers | Round the front strap, the middle finger tight under the trigger guard; the middle and ring fingers do most of the gripping | [Outdoor Life][ol], [Shooting Illustrated][si] |
| Shooting hand, index finger | Straight along the frame until the shot, then on the trigger | [Shooting Illustrated][si] |
| Shooting hand, thumb | Forward and high; with the support hand on the gun it rests on the root of the support thumb | [American Rifleman][ar], [Outdoor Life][ol] |
| The open side | The shooting hand leaves a gap on the grip's other panel, between its fingertips and the heel of its palm | [Shooting Illustrated][si] |
| Support hand, heel of the palm | Fills that gap: the pad under the thumb is rolled onto the bare panel | [Shooting Illustrated][si], [Outdoor Life][ol] |
| Support hand, four fingers | Wrap over the shooting hand's fingers, round the front of the grip, tight up against the trigger guard | [Outdoor Life][ol], [American Rifleman][ar] |
| Support hand, index finger | Under the trigger guard, as high as it goes; never hooked round the guard's front | [Athlon Outdoors][ao], [Outdoor Life][ol] |
| Support hand, cant | The wrist is bent forward (the little finger toward the ground), which puts the hand at about 45 degrees to the barrel and points the thumb at the target | [Athlon Outdoors][ao], [American Rifleman][ar] |
| Support hand, thumb | Forward along the frame under the slide, ahead of and below the shooting thumb; the thumbs never cross | [American Rifleman][ar], [Outdoor Life][ol] |

Sources differ on small things (how hard each hand squeezes, whether the support thumb presses on the frame); none
teaches the two hands side by side, the support fingers on the grip itself, or a support hand held like the shooting
hand mirrored.

[si]: https://www.shootingillustrated.com/articles/2011/11/18/thumbs-forward-handgun-grip
[ar]: https://www.americanrifleman.org/articles/2019/7/16/pro-shooter-advice-proper-handgun-grip
[ol]: https://www.outdoorlife.com/guns/how-to-hold-a-pistol
[ao]: https://athlonoutdoors.com/article/proper-pistol-grip-max-michel/

## The 3D Third Person pistol's hold {#the-template-pistols-hold}

<!-- new section: what of the taught grip the mannequin's hands do on the template's pistol, with the numbers
     (gdstudio #1084) -->

The pistol is the template's own (692 triangles, the muzzle along -X, up +Y, the gun's left +Z); the right hand's seat
is kit #1001's and did not move, since the rifle's hold is derived from it. Rebuilt on it, on both mannequins:

| Part | In the template | Measured (female, male) |
| --- | --- | --- |
| Support hand, cant | Its knuckle line is 43 degrees from the gun's own down (16 before, the right hand mirrored); the wrist is 4 cm higher, level with the frame | `test_the_two_hands_hold_the_pistol_together`: 25 to 50 degrees |
| Support hand, four fingers | Over the right hand's ring and little fingers and round the front of the grip, their tips on the gun's right | each middle and last bone within 5 mm of the right hand's skin (at most 1.4 mm off it) |
| Support hand, index finger | Under the trigger guard, on the gun | at most 1.9 mm off the guard |
| Support hand, palm | On the right hand's fingertips, which cover the left panel; the heel reaches the bare panel on the male mannequin only (0.8 mm; the female's thinner palm is 13 mm off it) | 2.4 mm (female) and 1.8 mm (male) off the right hand |
| Support hand, thumb | Forward along the frame above the trigger guard, under the slide, its last joint 108 mm ahead of the right thumb's | 1.1 mm off the gun (female), 0.9 mm in (male) |
| Shooting hand, thumb | Lifted off the frame onto the root of the left thumb while the left hand is on the gun (`pistol_thumb_pose.tres`); on the frame when the gun is held in one hand | 0.4 to 2.0 mm off the left hand, 4 to 9 mm from the skin of its thumb root |
| Depth | Each hand against the gun and against the other hand, both ways | at most 1.6 mm in |

What the rig cannot do, and where it differs from the taught grip:

- **The shooting hand's middle finger lies beside the trigger guard, not under it**, and hooks round the guard's
  front (kit #1001's seat: the web is under the tang, and the mannequin's hand is 41 mm from the web to the top of the
  middle finger where the gun is 63 mm from the tang to the guard's underside). The support index finger is under the
  guard all the same, over the right ring finger. A lower or canted seat would put the middle finger under the guard;
  it would also move the rifle's hold (kit #1213).
- **The trigger finger grazes the guard on its way to the trigger** (3.7 mm at the guard's front strut, for a few
  twentieths of the way): the finger's last bone is 20 mm thick and the guard's opening 21 mm long, so no way in is
  clear, with the knuckle free to 40 degrees back either (kit #1212). It no longer touches the left hand.

## Between the poses {#between-the-poses}

<!-- new section: what moves between the solved poses of the two-handed hold, and how each move is kept clear
     (gdstudio #1078, #1079, #1084) -->

A solved pose is clear where it holds; the blend the game plays between two of them is not, unless it is solved too.

- **The trigger finger goes by a pose between** (kit #1079, `pistol_trigger_way_pose.tres`,
  `HandPoseModifier.second_via`). The straight blend from along the frame to the trigger left the guard on the gun's
  far side: 7.3 mm through the left thumb's tip and 7.0 mm through the gun. The pose between (the finger lowered and
  drawn out to its own side, nearly straight) is solved as the nearest to both ends that keeps the finger out of the
  left hand at every twentieth (never nearer than 3 mm now) and as little in the gun as it can be (3.7 mm, above).
- **The right thumb makes room while the left hand waits** (kit #1084, `SupportHandPlan.room`). The left thumb's
  root takes the right thumb's place on the frame, so the right thumb is lifted onto it; blended while the left hand
  came in, it was 16 mm inside that hand. The plan now has a step for it: the hold's arm takes the left hand to the
  far end of its way (the plan's `on` to 0.3), the hand waits there while the thumb moves (0.3 to 0.6), then comes in
  (0.6 to 1); the way's far end is solved clear of the thumb everywhere between its two poses, and the thumb's own
  blend passes 1.9 mm through the gun at most (the solver holds the half-way pose to a holding finger's depth).
- **The left hand's fingers press the right hand as they open and close** over it: 2.1 mm at the right little
  finger's tip on both mannequins, for two hundredths of a reload (it is 1.5 mm in the palm that lies on it while both
  hold). The test allows 2.5 mm there by name (`LEFT_HAND_PASSING`), and only while the fingers are between their
  two poses.
- **An arm too short backs the hand off along its way** (kit #1078, `HoldArm.retreat`). While the aim comes up the
  gun is still out to the side and the left arm 6 to 16 cm short of the hand's place; the hand stopped short with the
  place's turn, its fingers 13 to 18 mm through the gun and the right hand. The arm now puts the hand on the line of
  its way, at the first place it reaches, opened (`HoldArm.backed_off`), so it comes in only as far as the arm
  reaches: 0.8 mm (female) and 0.9 mm (male) deep at most on the live player, every update, both mannequins.
- **The gun is not held out during a reload.** `carry_arm_out` (8 degrees, for the thigh) stayed on through a reload
  started with the gun carried and took the gun 13 mm out of the male mannequin's reach from the new place; it now
  fades with the reload's weight as it does with the aim's.

## The left hand through the reload {#the-left-hand-through-the-reload}

<!-- new section: moved from the weapons page, which is near the size limit (gdstudio #1084) -->

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
  base, nothing more than 1.2 mm in). The trigger finger is off the trigger for the whole reload. Where the hand
  should be at each moment was decided from the clip and from how a reload is taught: the magazine is fetched at the
  belt, guided in and seated firmly with the support palm, and the
  grip is taken again ([Shooting Illustrated](https://www.shootingillustrated.com/articles/2012/10/25/semi-automatic-handgun-reloading),
  [AmmoLand](https://www.ammoland.com/2023/03/4-pistol-reload-methods-9-magazine-tips)). The clip has no rack of the
  slide and no magazine in the hand; the magazines and the slide are the hold's
  ([below](#the-magazine-through-the-reload)).
- **The left hand has one way on and off the gun** (kit #1051). #1031 let the hand go by fading its arm to the
  clip's, so it left along whatever line lay between its place and the clip's hand, its little finger still on the
  grip: 5.1 to 5.2 mm through the gun at shares 0.05 to 0.055 on the female mannequin, and 9.1 mm (female) and 5.7 mm
  (male) at 0.7875 on the swing back from the magazine, between two hundredths. Now the fingers open where the hand
  holds (`pistol_open_pose.tres`: each finger the nearest pose that lifts it 5 mm off every surface with nothing
  deeper than 1 mm in the sixteen poses between, blended as the game blends them; the little finger, which lies on
  the grip's left panel, curls its middle joint in), then the opened hand leaves along a straight 6 cm line
  (`WeaponHold.support_way`: of the directions 10 degrees apart in which the whole hand stays clear, and its
  neighbours too, the one nearest the way to the belt; 26 degrees off it, down, back and to the left), and only at
  the line's far end does the clip's arm take it. Coming on is the same way backwards, for the aim and from the
  magazine alike: from under the magazine the hand drops, crosses to the line's far end bowed 4 cm down and out
  (`return_clearance`) while its fingers open, and comes in. `SupportHandPlan` holds this as one number (how far on
  the gun the hand is) and the reload's phases (`HELD`, `LET_GO`, `AWAY`, `REACH`, `INSERT`, `SEATED`, `RETURN`), for
  whatever moves with the hand next. Measured at every hundredth of the reload and at every quarter of a hundredth
  of the moving spans, the left hand is at most 1.2 mm in on both mannequins; on the live player reloading while it
  aims, on every update, the same (before: 5.9 to 8.5 mm over five frames of the let-go and 7.4 mm on the way back).
  Two faults the live measure found were not the left hand's way: the arm too short while the aim comes up (kit
  #1078) and the trigger finger through the left thumb (kit #1079), both [above](#between-the-poses).

## The magazine and the slide through the reload {#the-magazine-through-the-reload}

<!-- new section: the left hand acted out a reload with nothing in it and the pistol's magazine never left the grip;
     nothing said how a held part moves with a hand or what the slide does (gdstudio #1052) -->

What moves on and with the pistol through `Pistol_Reload` (kit #1052). All of it is `WeaponHold`'s, cosmetic and never
sent; the rounds still go in at the end of `reload_time`.

- **The old magazine drops when the reload's first sound plays** (the weapon definition's `reload_sound_at[0]`, 0.2 of
  the clip): the pistol's `Magazine` node is hidden and a body with its mesh (`DroppedMagazine`, a box of the mesh's
  size, on no physics layer and meeting the world and props, continuous collision) leaves the grip down its line at
  0.5 m/s plus the gun's own motion, falls about a metre and lies on the floor for `dropped_life` (8 s). One a
  character: the next reload takes the same body back, so a long fight leaves no pile.
- **The new magazine rides the left hand's bone** from the belt (0.25 of the clip, behind the hip from the player's
  camera) to the end of the way in: a `BoneAttachment3D` on `hand_l` with the pistol's magazine mesh, placed as the
  pistol's own magazine is seen from the `MagazineHand` marker. The hand's bone sits on that marker once the
  magazine is in, so in the hand it is exactly where the pistol's will be, and at the end of `INSERT` the hold swaps
  the two with nothing moving. The way in (`magazine_approach`) is the grip's own line (the `Grip` socket's -Y, 18
  degrees back from the gun's down), 12 cm: the magazine's length and its top 1.6 cm clear of the well, since the
  arm arriving at the line's start is a few millimetres off it (at 11 cm the top went 2.1 mm into the grip's foot).
  The hand and the magazine go up it together, the magazine within 1.5 mm of the line and 1 degree of the grip.
- **The fingers take it, carry it and let it go, three solved poses** (`tools/hold/solve_pistol_hold.py --carry-only`).
  At the belt the hold takes the fingers from the clip and opens them (`pistol_carry_open_pose.tres`, each finger the
  nearest pose 5 mm off the magazine with nothing in it on the way back), then closes them on it
  (`pistol_carry_pose.tres`): the index, middle and ring fingers' tips and the thumb on the magazine (within 1.2 mm in
  and 0.9 mm off), the base in the fist, its top out of the thumb side, as a magazine is held to be guided in; each
  finger is solved with the palm's vertices it moves measured too (a thumb measured alone pressed the palm by its root
  3.5 mm into the magazine). The little finger cannot reach it from the hand's place under the base (13 to 14 mm off)
  and the palm is 4.5 (female) and 6.3 mm (male) under the base. As the grip's foot comes down over the fingers they
  open again and go to the pose under the magazine over 0.3 to 0.5 of the way in (`carry_release`, the latest span
  searched that passes no deeper than the pose under the magazine itself: 1.0 and 0.9 mm).
- **A reload cut short leaves the pistol whole**: with no reload weight the plan has the pistol's magazine in its grip
  and none in the hand, whatever share the clip was at (`SupportHandPlan.magazine_in_gun`, `magazine_in_hand`).
- **The slide: moved by the hold, not by a hand.** The clip has no rack and the library no other pistol reload; a rack
  clip of the template's own is kit #1081. Of the two ways open until it lands, a release by the right thumb does not
  fit this model: its slide stop lever is on the gun's right side, under the right hand's fingers, and the right thumb
  lies high on the left side (on the left thumb's root while both hands hold). So the `Slide` node stands back 4 cm
  (`slide_travel`) while the pistol is empty, as a pistol's slide locks open on its last round, and runs forward when
  the reload's last sound plays (0.85, the slide's sound): the slide released. With rounds left it stays forward and
  only the sound plays. The rack clip of #1081 can drive the same node (`slide_part`) with the left hand.

Tests: `tests/gameplay/test_reload_magazine.gd` (the magazine's place, the fingers on it and the magazine against the
gun at every hundredth of the reload on both mannequins; the drop, the cut-short reload and the slide on the live
player) and `test_support_hand_plan.gd` (the plan's magazines). Close-ups: `tools/capture/pistol_hold_study.tscn`
with `HOLD_ONLY=reload` also films the hand and the magazine at the belt from the body's left, ahead, above and the
player's camera (`*_carry_*.png`).

- **Approach:** Measure a hand against the weapon as it is at that moment: while a part of it is out (a magazine in
  the other hand), against the weapon without it, and the part on its own. **Watch out for:** the tests' contact was
  made once with the pistol's magazine seated, so the left hand carrying the new magazine up the grip read 2.9 to
  3.6 mm inside a magazine that was no longer there. **Seen:** gdstudio #1052, 2026-11-11 (fix: a second contact
  made with the magazine hidden, used while it is out).
- **Approach:** Give a hand that closes on something an opened pose solved against it, and go to and from the closed
  pose by it: opened at the far end of a straight blend, closed only on the thing. **Watch out for:** blended
  straight from the clip's fist the fingers went 3 to 7 mm through the new magazine as they closed on it, and from
  the carry to the pose under the magazine 1.7 to 2.8 mm, whatever share of the way in the change was put at.
  **Seen:** gdstudio #1052, 2026-11-11 (fix: `pistol_carry_open_pose.tres` both ways; 1.0 mm at most).
- **Approach:** Put a mesh that rides the character (a prop in a hand) in the model slot, as the weapon's seat is, a
  `BoneAttachment3D` with its skeleton path set before it enters the tree, so the slot puts it on the body's render
  layers. **Watch out for:** the new magazine's attachment added under the skeleton after the slot had sorted its meshes
  stayed on layer 1: the minimap would have drawn it and the inventory's preview missed it (six cases of the full suite
  failed). **Seen:** gdstudio #1052, 2026-11-11.
- **Approach:** Make a test's prop measure from the node whose children are the meshes. **Watch out for:**
  `HandContact.set_weapon()` takes the meshes under the node it is given, not the node itself: given the magazine's
  `MeshInstance3D`, it measured nothing and every finger read 30 mm off. **Seen:** gdstudio #1052, 2026-11-11 (fix:
  the `BoneAttachment3D` that holds the mesh).

## Solving two hands against each other {#solving-two-hands}

<!-- new section: what the solver had to learn to measure one hand against the other (gdstudio #1084) -->

- **Approach:** Research how a real grip is formed, finger by finger with sources, before solving a second hand, and
  give the solver a cost for each thing the grip teaches (the cant, the fingers over the other hand's and round to
  the far side, the index finger under the guard, the thumbs). **Watch out for:** a second hand solved as the first one
  mirrored and moved until its fingers touched something met every contact limit and sat beside the first hand, its
  thumb along the trigger guard's opening; the maintainer's look at the game found it, the numbers did not.
  **Seen:** gdstudio #1084, 2026-11-11 (fix: the table above; cant 16 to 43 degrees).
- **Approach:** Measure each hand against the other, both ways, in the solver and in the test, and sample a part
  with large faces (the palm: 199 triangles, edges to 5 cm) all over its faces, not only at its vertices; measure the
  other hand's vertices against a finger taken as three capsules. **Watch out for:** the left hand's vertices against
  the right hand's skin read 1.2 mm while the right little finger's tip was 3.3 mm inside the left palm, and at the
  first canted place the right thumb's tip 17.5 mm; a capsule's middle line is 4 to 9 mm off the bone's, and its
  radius is the outer vertices' (the median is pulled in by the joint balls inside). **Seen:** gdstudio #1084,
  2026-11-11 (fix: `Hand.palm_points`, `Hand.finger_depth`, `measure("r", true)` in the test).
- **Approach:** Say in the cost where a finger must end, not only what it must touch. **Watch out for:** asked to
  lie on the other hand, the support fingers curled into their own palm (they touched the other hand's fingertips
  there), and the shooting thumb crossed to the gun's far side to lie on the support hand's fingertips, a place it
  could only reach through the gun. **Seen:** gdstudio #1084, 2026-11-11 (fix: the support fingers' last bones on the
  gun's far side, the thumb's on its own).
- **Approach:** Close a hand's skin where its selection ends before counting a point inside or out of it, each
  ring of open edges joined to its own middle, in the solver and in the game's measure alike, and look at the hold
  from above after every solve. **Watch out for:** the palm's piece is open at the wrist, and the shooting thumb
  turned sideways behind the gun and put its tip in that opening: the solver read it 0.7 mm off, the game's measure
  2.2 mm off in the level aim and 19.4 mm in once the aim turned the hands up (two of its three rays left through
  the hole). One fan for all the hand's open edges joins its pieces into one, where a point inside two counts as
  outside. **Seen:** gdstudio #1084, 2026-11-11 (fix: `wrist_cap`, `HandContact._open_rings`; the test checks the
  thumb's tip within 12 mm of the left thumb's root).
- **Approach:** Search a finger's pose from many starts (the grid, then some thousands of random ones, the best four
  refined each on its own), and aim it at a place a wide search proved it reaches. **Watch out for:** refined from the
  grid's best start alone, four different targets gave the same sideways thumb; a target the thumb could not reach
  (3 cm ahead of where its joints end) pulled it there as well. Its root is behind the grip, so its tip gets no
  further forward than the left thumb's root joint. **Seen:** gdstudio #1084, 2026-11-11 (fix: `solve_finger`'s
  `wide`, `THUMB_OVER`).
- **Approach:** Trace every blend the game plays between two solved poses at twentieths against the gun and the
  other hand before wiring it, and give a part that must move through another's place a step of the plan in which
  that other is away. **Watch out for:** the thumb's straight blend between its two poses passed 16.9 mm through the
  gun (the poses were on opposite sides); lifted as the other hand came in, it was 16 mm inside that hand at two
  hundredths of the reload. **Seen:** gdstudio #1084, 2026-11-11 (fix: `SupportHandPlan.room`).
- **Approach:** Measure a way's room before promising it clear: the part's thickness against the opening it enters.
  **Watch out for:** the trigger finger (20 mm) into the guard's opening (21 mm) grazes the guard's strut by 3.6 mm
  whatever pose it goes by; four searches (other trigger poses, a wider knuckle) found the same. **Seen:** gdstudio
  #1079, 2026-11-11 (the test allows that graze by name; the guard is #1212).
- **Approach:** Measure the other arm's reach on each mannequin's own skeleton, in the reload clip's first pose as
  well as the aim poses, after moving a hand's place. **Watch out for:** the solver's merged rig is the female
  skeleton with both skins, so the male arm was never measured: the canted place, 4 cm higher, was 6.5 mm out of
  its reach where the reload starts with the gun carried, and the hand stood off the gun with its fingers open.
  **Seen:** gdstudio #1084, 2026-11-11 (fix: `reach` on both rigs; no carry swing during a reload).
- **Approach:** Write a long solve's output after every stage. **Watch out for:** the file was written once at the
  end, and a run stopped by its time limit in the last stage lost forty minutes of solved stages; the writer then
  wrote the old file into the project. **Seen:** gdstudio #1084, 2026-11-11 (fix: `save` after each stage).
