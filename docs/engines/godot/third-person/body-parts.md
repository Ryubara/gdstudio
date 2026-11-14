# The character's parts

<!-- new section: the template page's table of parts reached the size limit (#1457); each row's place and
     notes moved here, for the character, the player and their modules -->

The full row of each part of [the 3D Third Person template](../third-person-template.md#what-is-in-it), moved from its
table of parts (#1457): where it lives (in `templates/3d-third-person/game/`, the base in `templates/3d-blank/game/`),
what it does, its inspector and the pages with the rest. The body and what it does: the character and the player that
drives it, the moves (prone, the slide, the vault), the model slot and its animation, the aim layer and the peek lean,
hits, health and the ragdoll, the footsteps, and the bodies and clips under `assets/`. A new inspector line goes in its
part's section here.

## Character {#character-part}

**Where:** `gameplay/character/` (`character.gd` + `character.tscn`, `character_dressed.tscn`,
`character_controller.gd`, `character_state.gd`, `character_tuning.gd`, `step_climber.gd`, `interactor.gd`,
`character_slide.gd`, `character_push.gd`, `character_death.gd`, `character_capsule.gd`; [the body's
modules](character.md#controller))

`Character` is the body whoever drives it: it is moved by `step(command, delta)` alone and reads no input and no camera.
`character.tscn` is the body alone (capsule, eye point, interactor, a weapon with no muzzle: what a server loads),
`character_dressed.tscn` inherits it and adds the model, animation, footsteps and ragdoll at the same node paths ([a
second kind of controller](character.md#second-controller)). One resource (`CharacterTuning`) holds every tuned number.
Signals: `jumped`, `landed`, `took_hit`, `health_changed`, `hit_received`, `interacted`, `item_collected`,
`state_changed`, `teleported`, `aim_changed`, `crouch_changed`, `prone_changed`, `died`, `revived`, `fell`. Health and
hits: [Hit zones](../third-person-hits.md). Crouch, aim and shoot: [below](shooting.md#crouch-aim-shoot).

## Player {#player-part}

**Where:** `gameplay/player/` (`player.gd` + `player.tscn`, `player_input.gd`, `player_command.gd`,
`player_tuning.tres`)

`Player` extends `Character`: `player.tscn` inherits the dressed character and adds `PlayerInput`, the one reader of the
actions and the camera. The player joins the group `player` (the HUD, the minimap and a camera zone look for it; another
character is not taken for it), starts at a `SpawnPoint` of that group and again when it says `fell`, and holds
`input_enabled` and `ragdoll_key`. Signals: those of `Character`. Crouch, aim and shoot:
[below](shooting.md#crouch-aim-shoot).

## Prone {#prone-part}

**Where:** `gameplay/character/character_prone.gd`, `prone_tuning.gd`, `prone_animation.gd`,
`gameplay/player/prone_tuning.tres`

Lying down and the crawl, a module of its own driven by the command's `prone` bit (Z, d-pad down, the Prone button).

The inspector (`Character` > Prone > `prone_tuning`): Crawl `crawl_speed` 1.0 m/s, `backward_share` 0.7,
`sideways_share` 0.8, `acceleration` 10, `deceleration` 12, `turn_speed` 3, `move_while_changing` off; Getting down and
up `enter_time` 0.5 s, `exit_time` 0.7 s, `air_time` 0.15 s; Body `height` 0.6 m, `radius` 0.28 m, `camera_height` 0.55
m; Aim `aim_allowed`, `fire_allowed`, `spread_share` 0.5, `aim_move_share` 0.5, `aim_turn_speed` 6, `look_up_limit` 12,
`look_down_limit` 40; Input `input_mode` (toggle, hold, hold crouch), `crouch_hold_time` 0.5 s, `jump_gets_up`,
`sprint_gets_up`. On `Animation` > Prone: the clips (`prone/Prone_Idle`, `prone/Crawl_Fwd`, `prone/Crouch_To_Prone`,
`prone/Prone_To_Crouch`), `prone_idle_pace` 1, `crawl_clip_speed` 0.618 m/s (the crawl's stride; played backwards
backing up) and `prone_libraries` (a model's own prone clips, by its scene file), `prone_shot_kick` 7 degrees and
`prone_shot_kick_time` 0.22 s; lying puts the weapon away until the body aims, and it aims with the held weapon's prone
aim clips (`WeaponDef` `prone_aim_clip` and its up and down clips; the library `prone_aim`, a file a body by
`prone_aim_libraries`), with a view of its own (`PlayerCamera` Prone aim), never the standing aim layer. A reload lying
plays its `prone_reload_clip`. [Prone and the crawl](moves.md#prone).

## Slide {#slide-part}

**Where:** `gameplay/character/character_slide.gd`, `slide_tuning.gd`, `gameplay/player/slide_tuning.tres`

Crouch pressed at a sprint slides: a module of its own (`CharacterSlide`) read from the command's held `crouch` against
the last tick's (no command bit), saved in `CharacterState.slide`, every number in `SlideTuning` (the `Character`'s
`slide_tuning`), `State.SLIDE`, the read-only `sliding`. [Sliding](moves.md#slide).

## Vaulting and mantling {#vaulting-and-mantling-part}

**Where:** `gameplay/character/character_vault.gd`, `vault_animation.gd`, `vault_settings.tres` with `vault_low.tres`
and `vault_high.tres`; the scripts `Vaultable`, `VaultSettings`, `VaultClip`, `VaultProbe` and `VaultPlan` are the
synced `addons/gds_game/traversal/`; the map's `VaultCourse`

Jump at a wall that carries a `Vaultable` vaults over it or mantles onto it, by its measured height, depth and landing
room; a wall without one is only jumped. The vaults play the template's own clips (`Vault_Low` under 1.0 m, `Vault_High`
above, then `Vault_Land`), fitted to the wall measured so the hands land on its top; each body plays the file solved on
it (`vault.glb`, `vault_male.glb`, `vault_quaternius.glb`; `Animation`'s `vault_libraries`).

Inspector: the `Vaultable` (allowed moves, faces, height and depth overrides, clips), `vault_settings.tres` (Trigger,
Detection, Vault, Mantle, Body groups; `low_clip` and `high_clip` open the two `VaultClip` resources: Keyed on,
Contacts, Hands) and `Animation`'s Traversal clips. [Vaulting and mantling](traversal.md).

## Model {#model-part}

**Where:** `gameplay/character/character_model.gd`

`Model` is a slot (a `Node3D`) that holds the glb and the pistol seat; replace the glb under it: [Replacing the
model](character.md#replacing-the-model). Every mesh under it is drawn on `body_layers` (layer 2), which the minimap's
live camera leaves out ([what a puppet costs](puppet-cost.md#puppet-cost)). `variant` shows another model of the same
rig in an inherited scene, which cannot delete its base's ([Replacing the model](character.md#replacing-the-model)).

Inspector: `CharacterModel` `body_layers`, `variant`.

## Animation {#animation-part}

**Where:** `gameplay/character/character_animation.gd`, `character_clips.gd`

An `AnimationTree` built in code (also in the editor, as a `@tool` script): a body state machine, a weapon layer built
from the held `WeaponDef`'s clips (the grip on one hand, the aim pose, the shots and the reload on the upper body,
lowered during a switch) and a one-shot action layer (a hit on the upper body only while crouched, lying or sliding:
`hit_layer.gd`). The carry is an inspector choice ([Crouch, aim and shoot](shooting.md#crouch-aim-shoot)); while aiming
on the ground `aim_brace` holds the upper body's turn (`AimBrace`) and `aim_stance` holds the legs still under a
standing aim (`AimStance`: the idle on its steadiest frame). `CharacterClips.ALL` names every clip: the libraries' 86,
the template's own prone, prone aim and vault clips, the clips of our own that replace the library's (the library `gds`)
and the five fixed library clips ([the fixed clips](clips.md#fixed-clips)).

## Aim layer {#aim-layer-part}

**Where:** `gameplay/character/aim/` (`AimLayer`, `AimOffsetModifier`, `AimLimits`, `AimPose`, `AimUprightModifier`),
`tools/capture/slide_aim_tour.tscn`, `tools/capture/aim_fold_tour.tscn`, `tools/bench/aim_layer_cost.tscn`

Points the held weapon at the aim in every move: after the clips it turns `spine_01` to `spine_03` (shares 0.3, 0.3,
0.4) by the pitch and yaw that put the muzzle on a point `converge_distance` (15 m) along the aim ray, within the move's
`AimLimits` (`Character.aim_limits`, from the move's tuning), placed after the hold's grip and before its support arm,
on by the aim's weight less a reload, solved on the aim pose alone below `drawn_from` (0.9) up (no fold back), held
through a shot's recoil and eased back over `release_time` (0.12 s). A slide keeps the body along the slide while the
aim is within the side limits; past them the body turns, or the shot is refused for a weapon whose
`WeaponDef.past_aim_limit` is `REFUSE_SHOT`.

Inspector of `AimLayer`: `chain`, `chain_weights`, `converge_distance`, `release_time`, `drawn_from`, `disabled`; Head
group `head_neck_share`, `head_max_turn`, `head_disabled` (an `AimHeadModifier` after the spine's turn holds the head
level along the aim on a straight neck while any weapon aims, `tools/capture/aim_head_tour.tscn`, [the aiming
head](aim-head.md#head-on-aim)); Upright group `upright_max_lean`, `upright_disabled`
([chest](aim-chest.md#aim-upright)). A pose on each machine: a puppet is turned by the aim's heading off the body, one
byte in an aiming player's entry ([Aim layer](shooting.md#aim-layer), [puppets](online-client.md#puppets)).

## Peek lean {#peek-lean-part}

**Where:** `gameplay/character/peek/`, `gameplay/player/peek_input.gd`, `peek_tuning.tres`

Q and E (pad: aim and the d-pad; touch buttons; hold or toggle) tilt the body from the hips: eye, camera, `PeekShape`
and shots go 0.35 m out, the feet stay; stepped, predicted, sent.

Inspector: `Character` > Peek > `peek_tuning` (`side_offset`, `max_angle`, `crouch_max_angle`, `pivot_share`,
`lean_time`, `while_crouched`, `move_speed`, `shape_radius`, `shape_start`, `wall_margin`, `input_mode`,
`left_shoulder`); `PeekLayer` `chain`, `chain_weights`, `keep`, `head`, `disabled`; `LeftShoulder` `pistol_shift`,
`disabled`; `RifleHeld` `left_chest_turn`, `left_pocket_in`, `RightPoleLeft`. [The peek lean](peek.md#peek),
[left](peek.md#left-shoulder).

## Hit zones {#hit-zones-part}

**Where:** `gameplay/hit_zones/` (`HitZones`, `HitZone`), `gameplay/character/hit_reaction.gd`; `HitRecord` and `Health`
in the synced `addons/gds_game/hits/`

Eleven body parts on the skeleton a shot finds once it meets the capsule, each with a damage multiplier; health and a
death that carries the shot into the ragdoll, a flinch for a hit that does not kill, pushes and marks on a lying body;
one small `HitRecord` is all a network sends. [Hit zones](../third-person-hits.md).

## Health and using things {#health-and-using-things-part}

**Where:** the synced `addons/gds_game/hits/health.gd` and `addons/gds_game/interact/interactable.gd`, as nodes in
`character.tscn`, `target.tscn` and `door.tscn`

`Health` (inspector: `enabled`, `max_value`, `invulnerable`, Regeneration `regeneration_per_second` and
`regeneration_delay`, Flinch `flinch_threshold`) is what a shot looks for on what it hit, and `Interactable` (inspector:
`prompt`, `enabled`, `point`) is what the interact button looks for; parts find them by type, never by a method name.
[Health](../third-person-hits.md#health), [Using things](interact.md#interactable).

## Ragdoll {#ragdoll-part}

**Where:** `gameplay/character/character_ragdoll.gd`, `ragdoll_braces.gd`, `ragdoll_pool.gd`, `Character.die()` /
`revive()`

Death as a hybrid: an animated capsule while alive, physical bones generated on the model's skeleton (or taken from a
pool of sets made after the level loads) on the first death, a blend back on getting up. Y or the `ragdoll` checkbox;
runs on Jolt. [Ragdoll](character.md#ragdoll).

## Sound {#sound-part}

**Where:** `gameplay/character/footsteps.tscn`, `gameplay/pickup/pickup.tscn`, `world/world.tscn`

`Footsteps` follows the skeleton's feet (from the `Model` slot) and plays its steps decoded (the synced
`addons/gds_game/decoded_sounds/`, [Audio: starting sounds](../audio.md#starting-sounds)), as the weapon's sounds and
the impacts' do, a `Pickup` plays its coin, a `WeaponPickup` its pickup sound, `Wind` plays the bed on `Ambient`; every
player is on a bus ([Audio](../audio.md#template-buses)).

## Assets {#assets-part}

**Where:** `assets/characters/prototype/` (GDStudio's own bodies: `form_female.glb`, the default, `form_male.glb` for
the enemies, the `joint` and `facet` looks and the chibi), `assets/characters/mannequin/` (Quaternius's
`mannequin_female.glb` and `mannequin_male.glb`, CC0), `assets/animation/universal/`

Third-party folders each with a `LICENSE.md`; [the bodies](character.md#mannequins). `assets/animation/prone/` holds
GDStudio's own prone and crawl clips, the `AnimationPlayer`'s library `prone`, one file a body (`prone_form_female.glb`,
`prone_form_male.glb`, and `prone.glb` and `prone_male.glb` for the Quaternius pair; [the
libraries](clips.md#animation-libraries)).

Inspector: `Animation` `prone_libraries` (a model's scene file to its prone library). `assets/animation/own/` holds the
clips that replace the library's, the library `gds`, with the toolkit that builds them: `Animation` > Clips >
`idle_clip`...`sprint_clip` and the two `crouch_` clips are `gds/` ones; `CharacterClips.stand_in()` puts the library's
back ([the toolkit](../../../tools/blender/animation.md#toolkit)). `assets/animation/rifle/` holds six rifle clips, the
library `rifle`, played under the two-handed hold ([clips under a
hold](../../../tools/blender/clips-under-a-hold.md#body-under-the-hold)).

## Prototype mannequins {#prototype-mannequins-part}

**Where:** `assets/characters/prototype/` (`<look>_<body>.glb`, `mannequin_import.gd`, `mannequin_twist.gd`, the build
scripts), `tools/mannequin/`, `tests/fixtures/body_measure.gd`

GDStudio's own bodies (male, female, chibi; looks `form`, `joint`, `facet`) on the library's rig plus twist bones,
sockets and IK targets; `form_female` and `form_male` are the template's bodies ([the bodies](character.md#mannequins)).

Inspector of `MannequinTwist` (under each model's `Skeleton3D`): `skip_beyond` 9 m (the twist bones rest beyond it; 0
never skips) and the modifier's own `active` and `influence`. `Skeleton3D.motion_scale` is set at import. [Prototype
mannequins](../../../tools/blender/prototype-mannequins.md).
