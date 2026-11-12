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
- **The thumb** (`WeaponHold.one_hand_pose`, `pistol_one_hand_pose.tres`; `HoldFit.one_hand_pose` for another body): in
  two hands the left thumb's root has the frame under the slide and the right thumb rests on it; in one hand the right
  thumb lies there itself, forward along the barrel. The pose is laid over the trigger finger's (the grip modifier's
  `second`), so it comes with the aim and goes for a reload, and it passes through the two-handed grip's
  `thumb_way_pose` on the way, clear of the frame's rear edge. The female body's is set by hand
  (`tools/hold/pistol_authored.json`, `one_hand`: 1.0 mm off the frame at the tip, 23 degrees off the barrel; her solved
  grip folds the thumb down the grip panel, 71 degrees off); the male body's solved grip already lies there (21
  degrees), so its fit has none.
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
  the barrel and no more than 2 mm in at twenty steps of the aim coming up; switched live on the player, where the
  muzzle is within 3 degrees of the aim) and `test_pistol_hold.gd`'s one-handed reload while aiming, measured on every
  update. `tools/capture/one_hand_tour.tscn` films the aim, three shots, the look up and down, a reload and the let-go
  (`ONE_HAND=0` two-handed, `ONE_HAND_VIEW=side|front|hand|right|thumb|above|below`, `MODEL=male`) and prints the
  barrel's pitch a tick. `tools/bench/hold_cost.tscn -- one_handed` measured about the two-handed aimed hold's cost, on
  a machine too loaded for a number per character (40 characters: 39 to 43 ms a frame against 42 to 74 aimed and 20 to
  30 with no hold); measure it again on a quiet machine.

- **Approach:** Build a pose the library has no clip for on top of the nearest clip, after the tree, keeping what the
  clip aims (the barrel's direction) and moving only where the body is; read the live pose for a test inside
  `skeleton_updated` and an attachment's place after it; work each bone's parent pose out once down a chain. **Watch out
  for:** a live test that read `get_bone_global_pose` after the frame measured the clip's left hand, 160 mm from the gun
  it held; the first stance walked the skeleton up from every bone it turned and cost about twice the two-handed hold
  until the chain's poses were carried along; `character_animation.gd` was 7 lines under gdlint's 1,000, so the kick's
  timing moved into `WeaponHold` (keep new weapon logic out of that file). **Seen:** gdstudio #1085, 2026-11-11.
- **Approach:** When a pose is built from several skeleton modifiers, prove it on the live player too (the muzzle
  against the aim point, as `test_aim_layer.gd` reads it), and after a merge that brings in another modifier, film the
  game and read the frames before trusting the staged suite. Place a modifier by the one it must follow
  (`grip_modifier()`), never by a list's first entry. **Watch out for:** the aim layer placed itself after the first
  modifier the hold made, which was the grip until the stance was made before it; merged, it ran between the two and
  left the one-handed barrel 24 degrees under the aim, and every test passed, since the stage that measures the hands
  has no aim layer. **Seen:** gdstudio #1274 on #1253, 2026-11-12 (fix: the layer after the grip, the miss tested on the
  player).
