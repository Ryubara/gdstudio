# One-handed shooting

<!-- new section: shooting.md was at its size limit; nothing else held how a weapon is aimed and shot in one hand
     (gdstudio #1085) -->

How the 3D Third Person pistol is held, aimed and shot in the right hand alone. Part of
[crouch, aim and shoot](shooting.md#weapons); the two-handed hold it replaces while aiming is
[the two-handed pistol grip](../../../tools/blender/weapon-hands/two-handed-pistol-grip.md).

## One-handed {#one-handed}

<!-- new section: the pistol was held only in two hands; nothing said how a weapon is aimed and shot in one hand
     (gdstudio #1085) -->

A weapon definition's `one_handed` (off by default, in the Hold group; it rebuilds the tree, so it switches in the
running game) holds it in the right hand alone while the character aims and shoots: the chest side-on, the arm out
along the barrel, the left arm free, and a kick at the wrist and the elbow on each shot. The free hand comes to the
weapon only for a reload. There is no one-handed pistol clip in the Universal Animation Library, so no new clip was
made: the stance is put on the two-handed aim clips after the tree.

- **The tree** (`WeaponDef.free_bones()`, from `FREE_ARM_BONE`, `clavicle_l`): with a one-handed weapon held, the aim
  and shot layers leave the left arm out of their filters, so it keeps the locomotion clip (it hangs and swings as the
  body moves); the reload's filter still takes it.
- **The stance** (`gameplay/weapon/hold/one_hand_stance.gd`, `OneHandStance`, a `SkeletonModifier3D` that `WeaponHold`
  makes before the grip only while `one_handed` is on): the three spine bones turn `side_on` (35 degrees, right shoulder
  forward) and the neck and head turn back by as much; the right arm is reached out to `one_hand_reach` of its length
  (0.96, the elbow at about 147 degrees) along the barrel's line through the shoulder, and the hand keeps the clip's
  rotation, so the barrel points where the aim clip points it (within 1 degree across the look range,
  `test_one_handed_hold.gd`); the left upper arm is held `free_arm_out` (10 degrees) out. Its weight is the aim's, less
  the reload's: the reload clip brings the gun in front of the chest as in two hands.
- **The aim layer** ([aim layer](shooting.md#aim-layer)) runs right after the grip (`WeaponHold.grip_modifier()`), so it
  reads the muzzle where the stance and the wrist's turn left it and turns the spine by what is left: the muzzle is on
  the aim one-handed as in two hands (5.7 degrees under level at the tour's level look in both).
- **The fingers: one placement for both bodies** (`WeaponHold.one_hand_pose`, `pistol_one_hand_pose.tres`, and
  `one_hand_way_pose`; `HoldFit.one_hand_pose` and `one_hand_way_pose` for another body): the trigger finger on the
  trigger, the grip fingers round the grip and the thumb forward along the frame under the slide (in two hands the
  left thumb's root lies there and the right thumb rests on it). The female body's placement is the one target. Each
  other body is fitted to it by `tools/hold/fit_one_hand.gd`: the female hand is measured in the gun's own space
  (every finger's middle and last joints and tip, `tools/hold/one_hand_match.gd`), then each finger of the other hand
  is turned (its spread and bends, as `tools/hold/pistol_authored.json` holds them) until those points land on the
  same places, holding the gun to the suite's limits. On the male body the last joints and tips are within 2.2 to 4.6
  mm of the female's (before: the thumb's tip 21 mm, the little finger's 16 mm). Two things stay the body's own,
  because the hand's size puts them there: the seat (the male palm is thicker and sits 8 mm farther out on the grip,
  so its knuckles are 3.5 to 6 mm from hers) and the middle joints (its first finger bones are longer, 8 to 10 mm
  apart). The pose is laid over the trigger finger's (the grip modifier's `second`), so it comes with the aim and
  goes for a reload. On the way up the trigger finger passes `one_hand_way_pose`, fitted to the female finger's stop
  the same way with both legs held clear of the gun, and the thumb passes its own body's `thumb_way_pose`, clear of
  the frame's rear edge: it leaves from that body's carried grip, whose thumb lies elsewhere on each body (kit
  #1262), and fitted to the female stop the male thumb went 6 mm into the frame. Neither finger grazes the trigger
  guard in one hand: at most 1.5 mm in, at the trigger (the male finger's own way rubbed it 2.1 mm deep; the
  two-handed way is [between the poses](../../../tools/blender/weapon-hands/two-handed-pistol-grip.md#between-the-poses)).
  Separate poses existed before because each body's hold is solved on its own (kit #1187), and the one-handed pose
  only patched a body whose solved thumb did not lie along the frame: the female's was set by hand, the male's solved
  thumb was kept, and nothing compared the two hands on the gun.
- **The kick**: each shot of the character's weapon (`Weapon.fired`) starts `WeaponHold.shot_kick`, which rises over the
  first 8 percent of `kick_time` (0.4 s) and eases back by its end (`WeaponHold.kick_at`); at its height the wrist turns
  the muzzle up `kick_climb` (10 degrees) and the wrist comes back `kick_back` (5 cm, the elbow bends) and up `kick_up`
  (3 cm), on top of the shot clip. Measured on the barrel with `tools/capture/one_hand_tour.tscn`: the two-handed shot
  climbs 15.8 degrees at its peak (the clip's own, the aim layer holding its turn through the shot), the one-handed one
  21.1, two ticks earlier.
- **The left hand** (`SupportHandPlan`): one-handed, the aim gives the plan nothing, so the hand is on the weapon only
  through a reload, by the same way as a reload begun from the carry; at the reload's end it leaves along its way as the
  reload fades and the stance comes back.
- **Proof and captures**: `tests/gameplay/test_one_handed_hold.gd` (off by default and the two-handed hold unchanged;
  the right hand within 2 mm in and 5 mm off in the aim, up, down and shoot clips on both mannequins; the left hand at
  least 15 cm from the gun; the chest turned 28 to 42 degrees; the kick; the magazine; the thumb within 35 degrees of
  the barrel, the thumb and the trigger finger no more than 2 mm in at twenty steps of the aim coming up; the two
  bodies' last joints and tips within 5 mm of each other on the gun; switched live on the player, where the
  muzzle is within 3 degrees of the aim) and `test_pistol_hold.gd`'s one-handed reload while aiming, measured on every
  update. `tools/capture/one_hand_tour.tscn` films the aim, three shots, the look up and down, a reload and the let-go
  (`ONE_HAND=0` two-handed, `ONE_HAND_VIEW=side|front|hand|right|thumb|above|below`, `MODEL=male`) and prints the
  barrel's pitch a tick. `tools/bench/hold_cost.tscn -- one_handed` costs about what the two-handed aimed hold
  does: over three interleaved rounds on both bodies, headless, 40 characters, the median frame's work was 3.44 ms
  one-handed, 3.26 ms aimed in two hands and 1.68 ms with no hold (about 44 and 39 microseconds a character).

- **Approach:** Build a pose the library has no clip for on top of the nearest clip, after the tree, keeping what the
  clip aims (the barrel's direction) and moving only where the body is; read the live pose for a test inside
  `skeleton_updated` and an attachment's place after it; work each bone's parent pose out once down a chain. **Watch out
  for:** a live test that read `get_bone_global_pose` after the frame measured the clip's left hand, 160 mm from the gun
  it held; the first stance walked the skeleton up from every bone it turned and cost about twice the two-handed hold
  until the chain's poses were carried along; `character_animation.gd` was 7 lines under gdlint's 1,000, so the kick's
  timing moved into `WeaponHold` (keep new weapon logic out of that file). **Seen:** gdstudio #1085, 2026-11-11.
- **Approach:** Give every body one placement on the weapon: fit each body's fingers to the default body's points in
  the weapon's space within the hold's limits (`fit_one_hand.gd`), keep per body only what hand size forces (seat,
  knuckles, middle joints), and test the bodies against each other (`PLACEMENT`). **Watch out for:** poses solved or
  set on each body alone drift apart unseen, since each passes its own limits: the thumb set by hand on the female
  and solved on the male held the gun 16 to 29 mm apart until the maintainer compared close-ups; a seat moved under a
  hand-set pose (kit #1262) put the female thumb 2.6 mm into the frame (refit after a seat change); a way stop fitted
  alone sent the male thumb 6 mm into the frame from its own grip (fit a stop with its legs). **Seen:** gdstudio
  #1274, 2026-11-12 (the maintainer's review; fix: the female placement fitted onto the male hand).
- **Approach:** When a pose is built from several skeleton modifiers, prove it on the live player too (the muzzle
  against the aim point, as `test_aim_layer.gd` reads it), and after a merge that brings in another modifier, film the
  game and read the frames before trusting the staged suite. Place a modifier by the one it must follow
  (`grip_modifier()`), never by a list's first entry. **Watch out for:** the aim layer placed itself after the first
  modifier the hold made, which was the grip until the stance was made before it; merged, it ran between the two and
  left the one-handed barrel 24 degrees under the aim, and every test passed, since the stage that measures the hands
  has no aim layer. **Seen:** gdstudio #1274 on #1253, 2026-11-12 (fix: the layer after the grip, the miss tested on the
  player).
