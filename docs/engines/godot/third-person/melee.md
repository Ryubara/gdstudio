# Melee blows

<!-- new section: shooting.md reached 55 KB when gdstudio #1254 (melee for every weapon) met main's tracer and rifle
     entries; a blow is a subject apart from aiming, firing and ammunition -->

The melee blow every weapon and the empty hands throw: what a blow is, when it lands and how it travels online. Part of
[the 3D Third Person template](../third-person-template.md); aiming, firing, ammunition and switching are on
[Crouch, aim and shoot](shooting.md).

## Melee for every weapon {#melee}

<!-- new section: the fists had a short ray on their fire button and no other weapon had a blow; nothing said how a
     blow is data, when it lands or how it travels online (gdstudio #1254) -->

Every weapon has a melee blow on the `melee` action (V, the pad's left stick click, the touch Melee button), and the
empty hands' fire button is the same blow. What a blow is belongs to the weapon's **category**, a `WeaponCategory`
resource (`gameplay/weapon/weapon_category.gd`; the template's are `categories/unarmed.tres`, `pistol.tres` and
`rifle.tres`): its clips (played one after another, blow by blow), their speed, reach, damage, push, cooldown, the hit
window and the swing's sound. A `WeaponDef` names its category (`category`) and reads the blow through `blow_reach()`,
`blow_damage()`, `blow_impulse()`, `blow_cooldown()`, `blow_hit_start()`, `blow_hit_end()` and `blow_clips()`; with
`override_melee` on it takes its own `melee_*` numbers instead (the clips stay the category's). A new category is a
new `.tres`; a weapon of a kind already there only names it. `Kind.MELEE` now means the fire button throws the
category's blow.

- **When it lands.** `Weapon.melee(origin, direction)` starts the blow (`melee_started(blow)`), cuts a reload short and
  holds the trigger and the reload until `blow_cooldown()` has passed (`melee_ready`, `meleeing`, `blows`). On each
  tick from `blow_hit_start()` to `blow_hit_end()` its ray, `blow_reach()` long, from where it started (moving with
  the body) along the way it started, meets the world; the first thing it meets takes it through the hit zones or a
  `Health` as a hitscan shot does (`hit_scanned` with `melee` true; friendly fire and the factions as for a shot), and
  the blow is over. A window with nothing in reach is a miss. A blow spends no round and leaves no impact mark.
- **Where it goes.** The character throws it from the chest (`Character.CHEST_SHARE` of its height) along the aim,
  not along the crosshair's ray, and turns to it as an aim does; a blow waits for no aim, and none is thrown lying
  down, staggered or vaulting (`Character.can_melee()`).
- **The step state.** `MeleeBlow` (`gameplay/weapon/melee_blow.gd`) holds the blow's time, cooldown, landing, count,
  way and start, saved with the weapon's (`CharacterState.weapon`, 13 values), so a server and a predicting client
  land a blow on the same tick.
- **The AI.** `AiAttack` melees from `blow_reach()` and presses the melee button (`AiController.melee`) as a player
  does, so its blow is the same data, with any weapon when its `melee` is on.
- **Online.** The press rides the command's byte 13 (`CommandCodec.G_MELEE_PRESSED`, `NetWire.VERSION` 8) with the
  shot block, so the server judges its origin and meets the AI where the attacker's screen drew it, moved on by the
  ticks from the press to the tick the blow lands (`ShotRewind.nearer(..., age)`). The others hear a 4-byte `MELEE`
  event (slot, seq) and their puppet plays its own clip (`Weapon.melee(..., true)`); what it met is a `HIT`. Nothing
  cosmetic is sent: which clip a screen plays is its own.
- **The animation.** `MeleeLayer` (`gameplay/character/melee_layer.gd`, `CharacterAnimation.melee`) is a one-shot on
  the upper body over the whole weapon layer (fade in 0.05 s, out 0.12 s); while it holds the body the aim weight the
  `WeaponHold` reads is taken away, so the left hand leaves the pistol and the finger the trigger.
- **The clips** are the template's own (`assets/animation/melee/`, the library `melee`, with its `README.md`):
  `Melee_Unarmed_Jab`, `_Cross` and `_Hook`, and `Melee_Pistol_Whip`, `_Backhand` and `_Jab`, made by script with
  their checks. The rifle's category has no clip until the rifle is a weapon of the template.

| Category | Reach | Damage | Cooldown | Hit window | Hits to kill: head, chest, arm, thigh |
| --- | --- | --- | --- | --- | --- |
| Unarmed | 1.1 m | 15 | 0.55 s | 0.14 to 0.30 s | 3, 7, 12, 10 |
| Pistol | 1.2 m | 25 | 0.70 s | 0.20 to 0.34 s | 2, 4, 7, 6 |
| Rifle | 1.4 m | 30 | 0.80 s | 0.22 to 0.34 s | 2, 4, 6, 5 |

The target, written first: no blow kills at once anywhere, the empty hands take three blows to the head and seven to
the chest, a gun's blow two and four (health 100, the head 3x, the arms 0.6, the legs 0.7). `test_melee.gd` holds the
table through the real blow and hit zones, and V, the pad, the touch button, the empty hands' click, the window, the
cooldown, the reload and the overrides; `test_net_melee.gd` the event, the refusal and the rewind at 150 ms each way
(a blow drawn on a running guard lands, and misses with the rewind off). Capture: `tools/capture/melee_tour.tscn`
(three pistol blows and three of the fists on an enemy grunt, from the game camera). Inspector: `WeaponCategory`
`display_name`, Melee (`melee_clips`, `melee_clip_speed`, `melee_reach`, `melee_damage`, `melee_impulse`,
`melee_cooldown`, `melee_hit_start`, `melee_hit_end`), Sound (`melee_sound`, `melee_volume_db`); `WeaponDef` Melee
(`category`, `override_melee` and the `melee_*` numbers). The weapon's `MeleeSound` player is one node more on a
living character (`NODES_ALIVE`).

- **Approach:** Throw a blow from the body's chest along the aim's direction, not from the crosshair's ray. **Watch
  out for:** the over-the-shoulder camera's ray passes about half a metre beside the body, so in the first capture
  every blow of both categories missed a grunt standing right in front of the player, while the suite (a camera
  straight behind) passed. **Seen:** gdstudio #1254, 2026-11-11 (fix: `Character._blow_origin()`).
- **Approach:** In an online test of a blow on a runner, lead it by the runner's speed times `blow_hit_start()`.
  **Watch out for:** the blow lands a few ticks after the press, so a blow pressed as the drawn guard was in front of
  the player met it 0.6 m on (4 m/s for 0.15 s) and missed with the rewind on and off alike. **Seen:** gdstudio #1254,
  2026-11-11 (`test_net_melee.gd`).
- **Approach:** Tile every frame of a blow from the game camera, its fades in and out too, and read the tiles
  before review; let a blow turn the body (`aiming`) without raising the aim pose (`MeleeLayer.aim_of`). **Watch out
  for:** the aim a blow raised switched the aim offset on over the carry pose for two frames before each blow and
  four after: the chest folded 66 to 70 degrees back, in an attached clip nobody read frame by frame; the Blender
  sheets cannot show it, and a 3 degree keyed lean was first taken for the whole cause. **Seen:** gdstudio #1254 (PR
  #1315), 2026-11-11, from the maintainer's review (`test_a_pistol_blow_never_folds_the_body_back`).
