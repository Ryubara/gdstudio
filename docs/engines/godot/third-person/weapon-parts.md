# The weapon parts

<!-- new section: the template page's table of parts reached the size limit (#1457); each row's place and
     notes moved here, for the weapons, their hold and their models -->

The full row of each part of [the 3D Third Person template](../third-person-template.md#what-is-in-it), moved from its
table of parts (#1457): where it lives (in `templates/3d-third-person/game/`, the base in `templates/3d-blank/game/`),
what it does, its inspector and the pages with the rest. The weapons: the `WeaponDef` and `Weapon` node with the rifle's
two-handed hold, the hands' hold on the pistol, the slide rack, the two weapon models, the pickup, and where a shot
lands. A new inspector line goes in its part's section here.

## Weapon {#weapon-part}

**Where:** `gameplay/weapon/` (`weapon.gd`, `weapon_def.gd`, `weapon_loadout.gd`, `pistol.tres`, `rifle.tres`,
`fists.tres`, `two_hand_hold.gd`, `rifle_held.tscn`), `gameplay/projectile/`, `gameplay/target/`

A weapon is a `WeaponDef` resource (numbers, the view's `recoil` share of the camera's kick, magazine, reserve, reload,
projectile or hitscan or melee, the clips and sounds). The `Weapon` node fires the one it holds along the ray its
character hands it (the human's crosshair, an AI's look; it reads no camera, and with no muzzle it fires from
`no_muzzle_offset` beside its `shooter`), counts the ammo, reloads and clicks when empty, and pools its projectiles; the
`WeaponLoadout` (`Loadout`) holds the slots and the fists and switches between them. Every weapon has a melee blow on V
(the pad's left stick click, the touch Melee button; the fists' fire button), its clips and numbers its
`WeaponCategory`'s (`gameplay/weapon/categories/`: unarmed, pistol, rifle), played by `MeleeLayer`, sent online as a
small `MELEE` event ([Melee](melee.md#melee)). Both are stepped by the character (`self_ticking` for a weapon alone).

Inspector: `Weapon` `definition`, Nodes (`muzzle`, `shooter`, `no_muzzle_offset`, `aim_mask`), `muzzle_flash_enabled`,
`projectile_cap`, `self_ticking`; `WeaponCategory` `display_name`, the Melee group's `melee_clips`, `melee_clip_speed`,
`melee_reach`, `melee_damage`, `melee_impulse`, `melee_cooldown`, `melee_hit_start`, `melee_hit_end`, `melee_sound`,
`melee_volume_db`; `WeaponDef` `category`, `override_melee` and its `melee_*` numbers; `Loadout` Nodes (`weapon`,
`model`, `character`) and Weapons (`slots`, `unarmed`, `start_slot`, `switch_to_new`); every number on the `.tres`, the
Fire group's `fire_mode` (single, burst, automatic), `burst_size`/`burst_rate`/`full_burst_per_press` ([fire
modes](fire-modes.md#modes)) and the Aim and zoom toggles (`can_aim`, `fire_needs_aim`, `fire_zooms`, `show_crosshair`,
`override_zoom` and its framing), the `hitscan` toggle with its range, mask and `tracer`; `give()` adds one at run time.
The rifle is held with both hands by `RifleHeld` (a `TwoHandHold` under `Model`: Stance `aim_pocket`, `low_pocket`,
`low_pitch`, `low_yaw`, `chest_turn`, `aim_lean_limit`, `carry_lean_limit`, `carry_time`, `carry_butt_margin`,
`arm_stretch`, `pull_limit`, `butt_pad`, `butt_depth`, `butt_margin`, `push_level`, `skin_spacing`, `reach_turn`,
`pitch_limit`, `raise_time`, `shot_hold_time`; Switch `stow_pocket`, `stow_pitch`, `stow_yaw`; Recoil `kick_distance`,
`kick_degrees`, `kick_recover_time`; Hands `grip_pose`, `trigger_pose`, `trigger_way`, `support_pose`, `open_pose`,
`magazine_pose`, `fingers_far_distance`; Reload `reload_belt`, `magazine_well`, `reload_clearance`, `reload_leave`,
`reload_out`, `reload_in`, `reload_return`, `magazine`; Bodies `fits` (the male's `rifle_fit_male.tres`; the scene's are
the female's); Bones; the `Pivot`, the hands' places `RightHandTarget`, `LeftHandTarget` and `MagazineHand`, and the
poles are nodes). [Ammo, reloading and switching](shooting.md#weapons), [Weapon pickups and a two-handed
hold](weapon-pickups.md#weapon-pickups), [The rifle in both hands](weapon-pickups.md#rifle-hands). A `Target` falls when
its `Health` runs out. The `Crosshair` is `ui/hud/crosshair.tscn`.

## Weapon hold {#weapon-hold-part}

**Where:** `gameplay/weapon/hold/` (`weapon_hold.tscn`, `WeaponHold`, `SupportHandPlan`, `HandPose`, `HandPoseModifier`,
`HoldArm`, `HoldFit`, `FreeHand`, `TorsoSkin`, `HoldArmCarry`, `ArmCarrySteady`, `ArmCarry`), `tools/hold/`

Closes the hands on the pistol after the clips: the right hand's fingers and wrist, the index finger onto the trigger as
the character aims (by a solved pose between, clear of the left thumb), the left hand on the gun while it aims or fires,
laid over the right one as a two-handed grip is taught (canted, fingers over fingers, index under the trigger guard,
thumbs forward, the right thumb on the left one's root, where it goes by a pose between set by hand), and through the
reload clip's steps while it reloads (on the gun, away for the magazine, under the magazine, back) with the magazines
(the old one dropped, the new one in the hand), the arm held out from the thigh while it is carried. The left hand goes
on and off the weapon one way (fingers open, then a solved clear line; it waits at the line's far end while the right
thumb makes room, and an arm too short for its place backs it off along the line), and `SupportHandPlan` names the
reload's phases.

Inspector of `WeaponHold`: the poses (`grip_pose`, `trigger_pose`, `trigger_way_pose`, `thumb_pose`, `thumb_way_pose`,
`support_pose`), `support_marker`, `support_arm`, `support_elbow`, `support_keep_elbow`, `open_pose`, `support_way`,
`carry_arm`, `carry_arm_out` (8 degrees), the Reload group (`magazine_pose`, `magazine_marker`, `magazine_approach`,
`return_down`, `return_clearance`, the shares `reload_leave`, `reload_reach`, `reload_insert`, `reload_return`), the
Magazine group (`magazine_part`, `carry_pose`, `carry_open_pose`, `carry_release`, `carry_arrive`, `reload_take`,
`reload_drop`, `drop_speed`, `dropped_life` 8 s, `dropped_mask`: the old magazine drops and falls, the new one rides the
left hand up the grip's line), the Slide group (`slide_part`, `slide_travel` 4 cm, `reload_slide`: locked open while
empty, released at the reload's last sound), [One hand](one-handed.md) group, `held_weight`, `aim_weight`,
`reload_weight`, `reload_share` and `free_weight` for a character posed by hand, `free_release_time` and
`free_return_time` for an action that reaches with the left hand ([an interact](interact.md#interact-held)), and Bodies
`fits` (one `HoldFit` a body: the male's `pistol_fit_male.tres`; the scene's own poses (the carry's among them), seat,
markers, `carry_release` and `carry_arrive` are the female's; the rifle's `TwoHandHold` takes the same kind of fit,
`rifle_fit_male.tres`). Solved for each body; within 2 mm in and 5 mm off on both prototype bodies in every clip; 5.6
microseconds a character carried and 12.6 aimed over 40; cosmetic, never networked ([the rule and the
numbers](../../../tools/blender/weapons.md#the-third-person-template-pistol), [the two-handed
grip](../../../tools/blender/weapon-hands/two-handed-pistol-grip.md)).

**The carry's steady arm** (gdstudio #1577). Carried in one hand (`CharacterAnimation.Carry.HAND_ONLY`) the arms
follow the locomotion clips and the pistol rides the forearm. `weapon_hold.tscn`'s `ArmCarry` node (`HoldArmCarry`)
makes an `ArmCarrySteady` on the skeleton right before the grip and weighs it from the hold's weights (the weapon
held, less the aim, a reload or the rack, and the left hand let go; none for a character posed by hand): each arm
bone's carry follows the clip's rotation over `follow_half_life` (0.3 s), and the bone is drawn at that carry turned
by `stride_share` (0.35) of the clip's swing about it, eased under `limit` (30 degrees) and settled over
`swing_half_life` (0.06 s); the other arm keeps `free_share` (0.7) under `free_limit` (50). The numbers are an
`ArmCarry` resource, `pistol_arm_carry.tres`, tuned live. While its weight falls the carry closes on the pose under it
as fast, so the aim comes up on its own blend. `test_pistol_carry_run.gd` walks, jogs and sprints through turns of 90
and 180 degrees, a stop, a start and an aim on both bodies and reads the gun hand in the chest's space: about 0.03 m
and 6 degrees an update while carried, at most 0.078 m and 8.3 degrees on the update a walk starts or stops (0.235 m and
44.5 before: the gait blend's dip on a turn and the reversal's look),
and over each steady stretch within 0.26 m and 52 degrees (0.53 m and 120 at a sprint before: down by the thigh, level
forward, up by the head). The rifle is held by its own hold; its hand turns 29 degrees in an update as a jog's reversal
begins, before and after this (a follow-up issue). Capture: `tools/capture/pistol_run_tour.tscn`.

- **Approach:** To make a weapon carried in one hand read as one carry, steady the arm bones after the tree: let each
  follow its clip's average and keep a share of the swing about it, and fade the steadying with the aim by closing the
  carry on the pose under it as the weight falls. **Watch out for:** a hand-only carry puts a pointing pose's wrist on a
  swinging forearm, so every stride, a reversal's sped-up look and the gait blend's dip on a turn threw the gun about
  (the numbers above); a carry that lagged the pose under it while it faded held the arm down until the aim was nearly
  up and moved it the rest in a tick (0.23 m). **Seen:** gdstudio #1577, 2026-11-17 (found by playing; fix:
  `ArmCarrySteady`, `HoldArmCarry`).
- **Approach:** Weigh the steady arm by a moving share as well as the hold (`moving_speed` 1 m/s, rising at once,
  falling over 0.6 s), and place its modifier right before the grip on every update (`HoldArmCarry.keep_before()`).
  **Watch out for:** a carry held while standing still swung the hands 0.16 m on a stand-up from the crouch and put the
  rifle's hands 0.43 m off during a weapon switch; the modifier's place among the skeleton's modifiers changes the pose
  (placed first of all: a 0.07 m jump; placed once, a body swap rebuilt the grip and left the steady after it on the
  male body: the same jump); a "fresh" test by a gap in frames broke under the animation throttle, so the carry resets
  when its weight reaches zero instead. **Seen:** gdstudio #1577 / PR #1582, 2026-11-17 (full suite on an early
  commit: `test_own_clip_blends.gd`, `test_rifle_hold.gd`).

## Slide rack {#slide-rack-part}

**Where:** `assets/animation/pistol/` (`pistol_rack.glb`, its build scripts), `gameplay/weapon/hold/slide_rack.gd`,
`pistol_slide_rack.tres` and `pistol_slide_rack_male.tres`

GDStudio's own clip `pistol/Pistol_Rack` (0.93 s, an overhand rack after `Pistol_Reload`) and one `SlideRack` resource a
body that says where that body's left hand is on the slide, how its fingers close on it and how far the slide is back at
every share of the clip. An empty reload ends with it
([kit #1337](../../../tools/blender/weapon-hands/pistol-slide-rack.md#the-slide-rack)).

Inspector of `SlideRack`: `clip`, `body`, `hand`, `travel` (0.045 m), `elbow`, The hand's way (`places`, `places_from`,
`places_to`, `reach`, `away`), The fingers (`grip_pose`, `open_pose`, `fingers_over`, `fingers_away`, `fingers_close`),
Shares of the clip (`leave`, `grip`, `pull`, `release`, `slam`, `back`), Bodies (`fits`); all written by the clip's
build. Within 2 mm in and 5 mm off on both bodies on every frame ([the
clip](../../../tools/blender/weapons.md#the-third-person-template-pistol)).

## Pistol {#pistol-part}

**Where:** `assets/weapons/pistol/`

GDStudio's own (MIT, from Deadnight's build script), 692 triangles, one palette material, sockets `Grip`, `Trigger`,
`Support`, `Muzzle`, `Eject`; `pistol_held.tscn` seats it in the palm on `hand_r` and holds the `SupportHand` and
`MagazineHand` markers ([Weapons](../../../tools/blender/weapons.md#the-third-person-template-pistol)).

## Rifle {#rifle-part}

**Where:** `assets/weapons/rifle/`

GDStudio's own (MIT, Deadnight's M4A1 build), 1,236 triangles and a 420-triangle far level, one palette material;
sockets `Grip`, `Support`, `Trigger`, `Muzzle`, `Eject`, `Butt`, the `Magazine` and `Bolt` as their own nodes; the stock
collapsed 5 cm so the arm reaches with the butt on the shoulder (kit #1177); `rifle.tscn` swaps to the far level at 10
m. Held with both hands by `gameplay/weapon/rifle_held.tscn` (kit #889), each hand closed on it by solved poses: [The
rifle in both hands](weapon-pickups.md#rifle-hands).

## Weapon pickup {#weapon-pickup-part}

**Where:** `gameplay/pickup/` (`weapon_pickup.gd` + `weapon_pickup.tscn`, `rifle_pickup.tscn`)

A floating, turning weapon over a glowing ring that gives its weapon (or only its rounds) to a character that walks into
it, and comes back.

Inspector: Weapon `weapon`, `rounds`; Item `item_id`, `tint` (the ring and the light); Look `spin_speed`, `bob_height`,
`bob_period`; Sound `sounds`, `pitch_variation`; Respawn `respawn_time` (20 s); the nodes `Visual`, `Shape`, `Glow`,
`Light`, `Sound`. The rifle's stands in the prototype map. [Weapon pickups and a two-handed
hold](weapon-pickups.md#weapon-pickups), [The rifle in both hands](weapon-pickups.md#rifle-hands).

## Impacts {#impacts-part}

**Where:** `gameplay/impacts/` (`impacts.tscn` in `world/world.tscn`; scripts in the synced `addons/gds_game/impacts/`),
`assets/shaders/impacts/`, `assets/materials/impacts/`, `assets/audio/impacts/`

Where a shot lands: a mark on what it hit (it rides a moved or pushed body and goes with a freed one), an effect and a
sound, picked by the kind of surface. [Bullet impacts](shooting.md#impacts).

## Effects {#effects-part}

**Where:** `gameplay/effects/effect_emitter.tscn`, scripts in the synced `addons/gds_game/effects/`;
`gameplay/effects/tracer_pool.tscn` (`TracerPool`, `TracerDef`)

One pooled player of one-shot effects (muzzle flash, impacts). [Effects](shooting.md#effects). The hitscan tracers: one
capped pool of streaks drawn by one `MultiMesh` (`Tracers` in `world/world.tscn`; inspector: `enabled`, `max_tracers`
32, `web_max_tracers` 16, `warm_up_frames` 3; `TracerDef`: `color`, `energy`, `width`, `speed`, `length`, `fade_time`,
`start_offset`). [The tracer](shooting.md#weapons).
