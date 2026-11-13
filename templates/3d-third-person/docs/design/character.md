# The character

What the template's character does, what to tune and where to change what it plays. The character's scenes and
parts are in `game/gameplay/character/`, the human's on top of them in `game/gameplay/player/`; the controller, the
camera, the animation and the touch controls are separate parts that talk through signals and input actions, so each
can be replaced alone.

## The parts

| Part | Where | What it does |
| --- | --- | --- |
| `Character` | `gameplay/character/character.tscn`, `character_dressed.tscn` | The body, whoever drives it (a `CharacterBody3D`): walks, runs, sprints, crouches, lies down and crawls, jumps, climbs low steps, rides a `MovingPlatform`, pushes a `PhysicsProp`, opens a `Door`, collects a `Pickup`, aims and shoots. Says what happens in signals. `character.tscn` is the body alone (no model: what a server loads); `character_dressed.tscn` adds the model, animation, footsteps and ragdoll, and is the scene to start an AI's character from. |
| `Player` | `gameplay/player/player.tscn` | The human's character: the dressed character with its `PlayerInput`. It joins the group `player` (the HUD, the minimap and camera zones look for it), starts at a `SpawnPoint` of that group and again when it falls out of the map, and holds `input_enabled` and `ragdoll_key`. |
| `CharacterTuning` | `gameplay/player/player_tuning.tres` | Every number a developer tunes, grouped, with ranges and units (below). A copy of the file gives a second feel. |
| `PlayerCamera` | `ui/player_rig/player_rig.tscn`, `gameplay/player/player_camera.gd` | A thin wrapper that sets the follow, orbit and wall settings on a Phantom Camera (`FollowCamera`) and turns it to the orbit input. Tune this node, never `Camera`. |
| `Ragdoll` | `gameplay/character/character_ragdoll.gd`, a node of `character_dressed.tscn` | Makes physical bones on the skeleton of the `Model` slot, from the model's own bones, on the character's first death, taking a set the `RagdollPool` (`ragdoll_pool.gd`) made after the level loaded (a character that never dies never carries them; one freed gives them back), and holds the skeleton while the player is dead. Nothing it makes is saved in a scene; its exports are the body's mass, damping, joint range, how many times each joint is held (`hinge_passes`, `cone_passes`: the extra joints are `ragdoll_braces.gd`), layers and get-up time. |
| `CharacterAnimation` | `gameplay/character/character_animation.gd` | Builds an `AnimationTree` from the player's state and plays any other clip on request. |
| `WeaponDef`, `Weapon`, `WeaponLoadout`, `Projectile`, `Target` | `gameplay/weapon/`, `gameplay/projectile/`, `gameplay/target/` | A weapon is a `WeaponDef` resource (`pistol.tres`, `fists.tres`: every number of a shot, the magazine, reserve and reload, its clips and sounds). A `Weapon` fires the one it holds along the ray its character aims by, the crosshair's for the player (pooled `Projectile` spheres, a hitscan ray, which `WeaponDef.hitscan` turns any weapon's shots into, or a blow), counts the ammunition, reloads and clicks when empty; a `WeaponLoadout` switches between the slots and the empty hands; a projectile pushes physics bodies and bounces or stops, and a `Target` falls over when it is hit. A definition names its model and muzzle under the `Model` slot, so a game adds a weapon with a `.tres` and a model node. |
| `HitZones`, `HitReaction` | `gameplay/hit_zones/`, `gameplay/character/hit_reaction.gd`, nodes of `character_dressed.tscn` | The body parts a shot can hit (a `HitZone` shape each on a bone: `zone`, `bone`, `offset`, `damage_multiplier`, `enabled`), looked for only when a shot meets the capsule, and how the body answers a hit: `death_push`, `push_most_speed`, `lying_push`, the flinch (`flinch_enabled`, `flinch_push`, `flinch_most_speed`, `flinch_strength`, `flinch_time`, `flinch_hold`). |
| `Impacts` | `world/world.tscn`, `gameplay/impacts/impacts.tscn` | Where a shot lands: a mark on the body it hit (it rides the body and goes with it), an effect and a sound by the kind of surface. A projectile reports its hit to it (the group `impacts`); `WeaponDef.impacts` and `Projectile.impact_effects` switch it off. Its numbers (how long marks last, how many, their size and material) and one `ImpactSurface` node a surface (`Default`, `Wood`, `Metal`, `Target`) are in the inspector, each with an `EffectDef` (the burst and the sound, played by the `EffectEmitter`); a body names its surface with the metadata `surface` or a group. |
| `EffectEmitter`, `EffectDef` | `world/world.tscn` (`Effects`), `gameplay/effects/` (the scripts: `addons/gds_game/effects/`, synced from the kit) | Plays one-shot effects from one capped pool: an `EffectDef` (a particles scene, a sound, a flash of light, a length) is played at a point or on a node, by the muzzle flash and every bullet impact, and by anything a game adds. The pool is smaller in the web build, lights are limited, an effect frees its slot when it ends, the first frames of the level draw each effect once unseen (`warm_up_on_start`) so the first shot does not stop the web build, and nothing is sent over the network. Its switches and caps are in the inspector. |
| Muzzle flash | `gameplay/weapon/muzzle_flash.tres`, `muzzle_flash.tscn` | A star and a spray of sparks (`CPUParticles3D`) and a light on the pistol's `Muzzle`, pointing out of the barrel. `Weapon.muzzle_flash_enabled`, and the definition's `muzzle_flash` (another `EffectDef` for another weapon) and `muzzle_flash_size`, tune it. |
| `Footsteps` | `gameplay/character/footsteps.tscn` | Plays a step each time a foot of the animated skeleton lands (walk, run, sprint, crouch walk), through three `AudioStreamPlayer3D` nodes on the `SFX` bus. |
| `Crosshair` | `ui/hud/crosshair.tscn` | A small white circle with a thin dark ring at the middle of the screen, drawn by the node itself and shown only while the player aims. |
| `Interactor` | `gameplay/character/interactor.gd` | Finds the nearest usable thing in front: a node of the group `interactable` with an `interact()` method (a `Door` joins when `player_can_use` is on). |
| `CameraZone` | `gameplay/camera_zone/camera_zone.gd` | Hands the view to another Phantom Camera while the player stands in a `TriggerZone`. |
| `PhysicsLayers` | `core/physics_layers/physics_layers.gd`, `project.godot` `[layer_names]` | The seven named layers and the masks: the player is on Characters and meets World and Props (two characters walk through each other, for networking), shots meet characters, props, the level and a dead body's bones, the camera's walls are World and Props, pickups and zones mask what they sense. Tune a body's layers in its scene's Collision group; the names show in the inspector. |
| `TouchControls` | `ui/touch/third_person_touch_controls.tscn` (inherits 3D Blank's `touch_controls.tscn`) | The phone controls: a floating stick, a look drag and buttons that press the game's input actions (Jump and Use from the base; Fire, Aim, Crouch and Prone added here). |
| The rifle | `assets/weapons/rifle/` | The assault rifle a `rifle_pickup.tscn` gives, held with both hands by `gameplay/weapon/rifle_held.tscn` (a `TwoHandHold`: the butt in the shoulder, the right hand on the grip, the left under the hand guard, a reload for the left hand): `rifle.glb` and its far level `rifle_far.glb` with the hand sockets (`Grip`, `Support`), `Muzzle`, `Butt` and the `Magazine` and `Bolt` as their own nodes; `rifle.tscn` shows the far level from 10 m. How the hold was chosen is in the folder's README. |
| The bodies and their clips | `assets/characters/prototype/`, `assets/characters/mannequin/`, `assets/animation/universal/` | GDStudio's prototype bodies in the `form` look (`form_female.glb` for the player, friendlies and puppets, `form_male.glb` for enemies; `CharacterBodies` names them), Quaternius's female and male mannequins (`mannequin_female.glb`, `mannequin_male.glb`) and the Universal Animation Library 1 and 2 (CC0), 86 clips, each with a licence entry. |

## Input

`PlayerInput` (a child of `Player`) reads actions, never devices: `move_left`, `move_right`, `move_forward`,
`move_back`, `jump`, `sprint`,
`walk` (a slow walk), `interact`, `crouch`, `prone`, `aim`, `fire`, `reload`, `next_weapon`,
`previous_weapon`, `toggle_unarmed`, `melee` and, for the camera, `look_left`, `look_right`, `look_up`,
`look_down` and `shoulder_swap`. Each has a key and, where it makes sense, a pad binding for any device; the touch
layer presses the same actions. Rebind them in Project Settings > Input Map.

| Action | Keyboard and mouse | Pad | Touch |
| --- | --- | --- | --- |
| Move | WASD or arrows | left stick | the left thumb: a stick appears where it lands |
| Look | mouse (click the game to capture it; Esc lets go) | right stick | drag on the right half of the screen |
| Jump (and vault or mantle, near a wall that allows it) | Space | A | the Jump button |
| Sprint | Shift | left bumper | push the stick out to its outer ring |
| Walk | X (held) | a gentle push on the stick | a gentle push on the stick |
| Interact | E | X | the Use button |
| Crouch | C (held; a toggle in the tuning) | B | the Crouch button |
| Prone | Z (a toggle; a hold, or a long hold of crouch, in the prone tuning) | d-pad down | the Prone button |
| Slide | C at a sprint (Shift held, or any run faster than 5 m/s) | B at a sprint (left bumper) | the Crouch button with the stick at its outer ring |
| Aim | right mouse button (held) | left trigger | the Aim button |
| Fire | left mouse button | right trigger | the Fire button (it aims too) |
| Reload | R | Y | the Reload button (an empty magazine with rounds in reserve also reloads by itself) |
| Next weapon | mouse wheel down | d-pad right | the Swap button |
| Previous weapon | mouse wheel up | d-pad left | none |
| Empty hands and back | H | d-pad up | none |
| Melee (with any weapon; the empty hands' fire is the same blow) | V | left stick click | the Melee button |
| Swap shoulder | Q | right stick click | none |
| Die and get up (a testing aid) | Y (`Player`'s `ragdoll_key`; None turns it off) | none | none |

The character moves toward where the camera looks and turns to face its movement; while it aims it faces where the
camera looks instead, however it walks (the clips only walk forward, so a sidestep slides).

## Sliding {#slide}

Crouch pressed while running at 5 m/s or more (a sprint is 6.5) starts a slide: the body drops to 0.9 m in 0.12 s, gets
1.5 m/s more speed (at most 8.5 m/s, and only once every 2 s), and slows by friction for about a second and 5 m on the
flat. Down a slope it speeds up (to 11 m/s at most) and has no time limit; up one it stops sooner. The stick turns it
slowly (1.2 rad/s). It ends when it drops below 3 m/s, after 1.5 s on the flat, when crouch is let go (the default
hold mode; off, a press slides to the end) or when the body leaves the ground; it then crouches while crouch is held
or a ceiling is too low to stand under, and stands otherwise. Under a gap too low even to crouch in, it keeps sliding
until it is out. Jump during a slide jumps 85 percent as high and keeps the slide's speed through the air (at most
9 m/s, fading by 1 m/s each second). Aim and fire work while sliding: the body slides on along its line and the upper
body turns so the pistol points at the crosshair, up to 75 degrees to either side; aimed further round, the body turns
with the aim (or, for a weapon whose `past_aim_limit` is `REFUSE_SHOT`, the trigger does nothing until the aim is back
in reach). Another slide waits 0.3 s.

It is part of the body's step (`CharacterSlide`, `gameplay/character/character_slide.gd`): a bot or a server slides a
body by sending a command with `crouch` at speed, and `CharacterState.slide` holds its state. Every number is in its
`SlideTuning` (`gameplay/player/slide_tuning.tres`, the Player's `slide_tuning`; below); the camera's slide view is on
`PlayerCamera` (Slide group: 5 degrees wider over a quarter of a second); the clips are `CharacterAnimation`'s
`slide_start_clip`, `slide_clip` and `slide_exit_clip`. Turn it off with its `enabled`. Where the numbers come from
(shipped games' slides, with sources) is in the kit's `docs/engines/godot/third-person/character.md` (Sliding).

## Commands: what moves the body {#commands}

A `Character` (the `Player` is one) reads no key and no camera. Once a physics tick it asks its `controller` for a
`PlayerCommand` and steps it (`Character.step(command, delta)`), and that is the only thing that moves it:

| In the command | What it is |
| --- | --- |
| `move` | The stick in the view's own axes: x to the right, y forward, no longer than 1. |
| `yaw`, `pitch` | Where the view looks, radians: 0 looks along -Z, a positive pitch looks up. The body turns `move` by `yaw`, and faces `yaw` while it aims. |
| `sprint`, `walk`, `crouch`, `prone`, `aim`, `fire`, `jump` | Held. `crouch` and `prone` are already the result of their toggles. |
| `jump_pressed`, `fire_pressed`, `interact_pressed`, `ragdoll_pressed` | Pressed on this tick: true in one command only. |
| `has_shot`, `origin`, `shot_yaw`, `shot_pitch` | The crosshair's ray, on a tick where a shot may leave. |

`PlayerInput` makes it from the actions and the camera that draws the view (camera shake taken out), so the game
plays as before. To drive a character another way, give it another controller: a node that extends
`CharacterController` and returns a command from `sample()` (`PlayerCommand.set_from_world(walk, look)` writes the
view and the push from directions in the world), or turn the body's own stepping off (`set_physics_process(false)`)
and call `step` yourself each physics tick, as a server does. A `character_dressed.tscn` with a controller of its
own walks while you play, and is not taken for the player: only `player.tscn` joins the group `player`.

A character aims where its command looks, never where a camera does: `Character.aim_ray()` is the command's shot block
(the crosshair's ray, for the player) or, with none, a ray from the character's eye along `yaw` and `pitch`, and the
body fires its `Weapon` along it (`Weapon.fire(origin, direction)`). The aim pose follows the same `pitch`. So a second
character driven by commands shoots at what it looks at, with or without a camera in the scene.

`input_enabled` (on `Player`) turns the keys, pad and touch off; commands from anything else are stepped as they are.
`ragdoll_by_command` (on) lets a command's `ragdoll_pressed` kill and revive, which is what the Y key sends; a game
that steps commands from a network turns it off. `Character.state_snapshot()` and `restore()` take and put back what
the
next step reads, the weapon's cooldown and its place in the spread among it.

## What to tune {#tuning}

Open `gameplay/player/player_tuning.tres` in the inspector. The groups, with the defaults:

| Group | Settings (default) |
| --- | --- |
| Ground | walk speed (1.7 m/s), run speed (4.0), sprint speed (6.5), acceleration (28), deceleration (36), turn speed (12 rad/s), the stick push under which it walks (0.45), the least share of the walk a light push gives (0.5), how far above the walk speed a run starts (0.35 m/s) |
| Jump | jump height (1.25 m), rise time (0.4 s; height and time give gravity), fall gravity scale (1.35), short-jump scale (0.5), coyote time (0.12 s), jump buffer (0.14 s) |
| Air | air control (0.45) |
| Slopes and steps | max slope (48 degrees), step height (0.32 m), snap length (0.35 m), how far past the capsule the step check looks (0.06 m) |
| Crouch | crouch height (1.1 m), crouch speed (1.5 m/s), time to crouch and stand (0.2 s), toggle or hold (hold), the camera target's height standing (1.55 m) and crouched (0.9 m), and above a dead body's hips (0.25 m) |
| Aim | the share of the walk kept while aiming (0.6), turn speed to the camera (18 rad/s), the time the arm takes to come up and go down (0.15 s), how long a press of fire is kept while the arm comes up (0.3 s), the fastest aimed walk in walking speeds (1.5), how far up the arm must be to shoot (0.5) |
| Pushing | push strength (0.85), push mass (40 kg), the boost of the share (1.5) and the least share of a heavy prop (0.15), how much faster than a slow prop the body walks (1.15) and how long a slow push lasts after the last touch (0.25 s) |
| Actions | interact time and reach, hit stun, knockback, the landing speed that plays the landing clip, how long the landing lasts (0.3 s), the speed under which it counts as standing (0.15 m/s) |
| Body | capsule radius (0.34 m) and height (1.8 m) |
| Safety | the height below which it starts again at its spawn point (-25 m) |

Prone has a resource of its own, `gameplay/player/prone_tuning.tres` (`Player` > Prone > `prone_tuning`); the
defaults come from shipped games, with the sources in the kit's `docs/engines/godot/third-person/moves.md#prone`:

| Group | Settings (default) |
| --- | --- |
| Crawl | crawl speed (1.0 m/s), the share of it backwards (0.7) and sideways (0.8), acceleration (10) and deceleration (12), turn speed on the ground (3 rad/s), crawling while going down and up (off) |
| Getting down and up | the time to lie down (0.5 s) and to get up to crouch (0.7 s), the time off a ledge before a lying body gets up (0.15 s) |
| Body | the lying capsule's height (0.6 m) and radius (0.28 m), the camera target's height lying (0.55 m) |
| Aim | aiming (on) and firing (on) lying down, the share of the weapon's spread (0.5), the share of the crawl kept aiming (0.5), the aim turn (6 rad/s), how far it looks up (12 degrees) and down (40) |
| Input | toggle, hold, or a hold of crouch (`crouch_hold_time`, 0.5 s) with a press of crouch to get up; a jump press (on) and a sprint press (on) get up |

The slide has one too, `gameplay/player/slide_tuning.tres` (`Player` > Slide > `slide_tuning`); the defaults come from
shipped games, with the sources in the kit's `docs/engines/godot/third-person/moves.md#slide`:

| Group | Settings (default) |
| --- | --- |
| Start | on or off (on), the least speed (5.0 m/s), sprint needed (off), while aiming (off), on landing with crouch held (on), hold to continue (on), the wait between slides (0.3 s) |
| Boost | the boost (1.5 m/s), up to (8.5 m/s), once every (2 s) |
| Friction and end | friction (3.5 m/s²) and drag (0.3 per second), the fastest (11 m/s), the end speed (3.0 m/s), the longest on the flat (1.5 s; 0 lets friction end it) |
| Slopes | no limit downhill (on), slope gravity (9.8 m/s²), the share of friction downhill (0.2), the flattest slope that counts (4 degrees) |
| Steering | the turn rate (1.2 rad/s) |
| Body and camera | the capsule's height (0.9 m), the time to drop and rise (0.12 s), the camera target's height (0.75 m) |
| Shooting | shooting allowed (on), the aim layer's reach (`aim_limits`: 75 degrees left and right of the slide, 50 up, 70 down) |
| Slide jump | slide jump (on), its height share (0.85), boost (0), most speed (9 m/s) and air drag (1 m/s²) |

The character lies down only on the ground and gets up through crouch, only when a crouched body fits above it: under
a gap only a lying body fits under (0.8 m, say), letting go of prone keeps it down until it crawls out.

The aim layer (`AimLayer`, a node of the character, `gameplay/character/aim/`) points the held weapon at the aim in
every move: it turns the spine after the clips by the yaw and pitch that put the muzzle on a point 15 m along the aim
(`converge_distance`), within the move's `AimLimits`: `CharacterTuning.aim_limits` standing and `crouch_aim_limits`
crouched (70 degrees each side, 45 up and down), `SlideTuning.aim_limits` and `ProneTuning.aim_limits`. Each holds on
or off, the most to the left and right of the way the body faces, and the most up and down. The weapon's
`past_aim_limit` (Aim group of its `WeaponDef`) says what happens past the side limits: the body turns (the default)
or the shot is refused. Its own inspector: the chain of spine bones and their shares, `converge_distance`,
`release_time` (how fast it takes over again after a shot's recoil) and `disabled`.

While the character aims, with any weapon (the fists too), the aim layer also holds the head level and looking along
the aim, on a straight neck, whatever head the clips carry: in its Head group, `head_neck_share` and
`head_crouch_neck_share` (the neck's share of the turn, 0.4 standing and 0.5 crouched), `head_max_turn` (the most the
head turns off the line the chest gives it, 90 degrees) and
`head_disabled`. A weapon whose definition says `aim_head` `SIGHT` (the rifle) has the head brought on from there
toward its sights, the eye to the weapon's `aim_eye` marker: a cheek on the stock.

Vaulting and mantling have their own resource, `gameplay/character/vault_settings.tres` (the `Character`'s
`vault_settings`, in its Traversal group; empty turns them off), described in [Vaulting and mantling](#vaulting).

Every number is read while the game runs, so you can change it in the remote inspector and see it at once; the capsule,
the steepest slope and the floor snap are applied again whenever the resource changes. The `Interactor`'s half angle
(how far from straight ahead still counts as in front, 75 degrees) is on that node.

A `PhysicsProp` has a `push_speed` of its own: the cubes of the map are 60 kg, grippy (friction 0.5) and pushed at 1.2
m/s, so the character (15 percent faster than the cube, to stay against it) walks slowly into them and the push clip
plays for as long as it keeps going (0 leaves a prop to the character's push strength, as the spheres are). The pistol's
definition (`gameplay/weapon/pistol.tres`) holds the shot's numbers: fire rate (4 a second), semi or full automatic,
spread, damage (34 before the hit zone's multiplier), aim range, the push it gives a body (40 N·s), the magazine (12),
the reserve (36, at most 96, filled by a `Pickup` of `pistol_ammo`), the reload (1.6 s, by itself when the magazine is
empty), the switch (0.2 s down, 0.25 s up), the projectile's speed (45 m/s), size, colour, gravity (0, so it flies
straight at the crosshair), lifetime and bounces, the clips and the sounds (five shots at a small random pitch, two
empty clicks, the reload's three steps, the draw). Every weapon has a melee blow (V) whose clips and numbers are its
category's (`gameplay/weapon/categories/`: the fists' jab, cross and hook 1.1 m for 15, the pistol's whip, backhand and
jab 1.2 m for 25), and the fists (`fists.tres`) throw it on the fire button too, with no ammunition and without zooming
the view (`fire_zooms` off). Each definition's Aim and zoom group says what aim and fire do with it: `can_aim`,
`fire_needs_aim`, `fire_zooms`, `show_crosshair`, and with `override_zoom` its own aim and fire field of view, distance
and `zoom_offset` in place of the camera's; all apply while the game runs. The `Weapon` node keeps the rest:
`no_muzzle_offset` (where a shot starts when the weapon has no `muzzle`, as on a character with no model: beside its
`shooter`, this far off the aim ray), `projectile_cap` (24 in flight) and `self_ticking` (on: the weapon counts its own
cooldown and reload; the `Character` turns it off and counts them in its step); its `ShotSound`, `EmptySound`,
`ReloadSound`, `DrawSound` and `MeleeSound` nodes hold the volume, bus and voices. The `Loadout` lists the slots (the
pistol) and the empty hands (the fists).

The sample map is built for these numbers (blocks 1 m apart in height, twelve steps of 0.25 m, a 14 degree ramp): a test
fails when a tuning breaks it, which tells you which part of the map to rebuild.

The camera's settings are all on the `PlayerCamera` node, so you never open the Phantom Camera node: the nodes it
works with (Nodes), distance (1.7 m), the arm's offset (`offset`, in world axes; it moves the wall cast, so keep it
near zero sideways), field of view, near and far clip and start pitch (Framing), the **Shoulder** group, damping
(Follow), mouse, stick and pitch limits (Orbit), the priority and the blend back from a `CameraZone`'s camera
(Blending), the wall mask, shape and margin (Walls), and three views that blend on top of the framing: Sprint (the
field of view and distance added at a full sprint, the zoom speed, and a shake with its amplitude in degrees,
frequency and blend speed, off at 0, held on the `CameraShake` node under `PlayerCamera`), Slide (the field of view
added while sliding, 5 degrees, and its speed, 4 a second; the sprint view stays through a slide), Aim (the distance, the
field of view and the speeds in and out, and `aim_shifts_shoulder`, off) and Fire (the same for a shot fired without
aiming, with `zoom_when_firing` to turn it off, which a weapon's `fire_zooms` can also do for itself, and a Shot
kick: `shot_kick_amplitude` in degrees, off at 0, and
`shot_kick_duration`). Any other shake in the game is one line, `CameraShake.shake(preset, at)`, with a `ShakePreset`
from `core/camera_shake/presets/`; `CameraShake.strength` (0 to 1) is the player's setting for all of it. The zoom
follows the buttons: it starts back out on the next frame after aim and fire are let go, and so does the character:
its walk speed, turn and clips are the normal ones at once and only the arm lowers over the aim pose time (a shot
needs the arm half up, so a tap shorter than about 75 ms shoots nothing).

**Where each framing value lives.** The distance is on `PlayerCamera`. The over-the-shoulder view is the `Camera` node's
own **H Offset** and **V Offset** (they shift the view without moving the camera or its wall cast), and `PlayerCamera`
sets them from its Shoulder group: `shoulder` (left, center, right; Q or a click of the right stick swaps left and
right), `shoulder_offset` (0.5 m to the side), `vertical_offset` and `shoulder_time` (the seconds a swap takes, 0.3; 0
swaps at once). A swap made while aiming at a character keeps what the crosshair is on under it (Shoulder swap
subgroup; a swap while walking or sprinting only slides the view, so the run keeps its way, unless
`keep_aim_when_not_aiming`, off, is on). What counts as a character is `keep_aim_layers` (the Characters and Ragdoll
layers: the player, friends, enemies and a limp body); aimed at a wall, the floor, a prop or the sky the swap moves the
view to the other shoulder without turning it. `keep_aim_on_swap` (on) finds the point under the crosshair when the
swap starts (what the weapon would hit; never nearer than `aim_point_min_distance`, 2 m, past the arm, on
`aim_point_mask`, looked for up to `aim_point_range`, 100 m) and turns the view inward as it slides so the point stays
put, so a shot fired mid-swap goes there; `aim_shoulder_time`
(0.15 s) is the swap's time while aiming; `swap_anchor_strength` (1) is how much of that turn is made; `swap_look` says
what the player's own look does during the swap: `ADD` (the default) turns the view by it on top of the anchor, `RELEASE`
does too until it adds up to `swap_release_angle` (4 degrees) and then lets the point go. Tune
the shoulder there, in the editor or in the remote inspector while the game runs; nothing else writes those two values
(the Phantom Camera host copies its lens resource onto `Camera` whenever it changes, so `PlayerCamera` keeps the
resource equal to them). With `aim_shifts_shoulder` on, aiming also moves the view to `aim_shoulder`. The settings are
applied to the `FollowCamera` Phantom Camera when the game starts and again each time one changes, and the node is a
`@tool` script, so changing the distance, the field of view or the shoulder in the editor moves the camera in the
viewport. `Camera` renders and `PhantomCameraHost` copies the active Phantom Camera onto it, so a change to `Camera`'s
field of view is overwritten: tune `PlayerCamera`. Anything else about it (noise, tweens, dead zones) is that node's own
inspector, and the addon's docs are at <https://phantom-camera.dev>.

The touch layer is a scene you arrange in the 2D editor (`ui/touch/third_person_touch_controls.tscn`, which inherits 3D
Blank's `touch_controls.tscn` and adds the Fire, Aim, Crouch and Prone buttons): drag the `TouchStick` to move where the
stick waits, drag or resize the buttons under `SafeArea/Buttons` (instance `touch_button.tscn` for a new one and set its
action and word), resize the `MoveZone` and `LookZone` panels that decide which finger does what. Its numbers are on
`TouchControls` in `ui/player_rig/player_rig.tscn`: when it shows, the stick's radius, dead zone and sprint ring, the
look sensitivity and smoothing, the opacity and the margin from the screen edge.

## Dying and the ragdoll {#ragdoll}

`player.die()` makes the character limp: the animation stops, the capsule turns off, every gameplay input is ignored
(the camera still orbits, and follows the hips), and the body falls as a ragdoll keeping the momentum it had.
`player.revive()` gets it up where it lies, facing the way its chest faces, and the pose blends back to the animation.
Ticking `ragdoll` on a `Character` (the `Player` too) in the inspector (also while the game runs, in the remote
inspector) or pressing Y does the same; `teleport()` and `respawn()` get it up at once. The physics engine is Jolt
(`project.godot`): the ragdoll's joints are stable there and were not on Godot Physics. Each joint is held six times a
step (`hinge_passes`, `cone_passes`), so a limb the body lands on stays near a person's range. The prototype level has a
ramp and a ledge in the south (`RagdollLedge`) to run off. The way it is built and tuned is in the kit's
`docs/engines/godot/ragdoll.md`.

The living walk through the dead: no capsule meets a ragdoll bone, so a pile never slows, lifts, vaults or turns the
player. The player's `CorpseNudge` node pushes the dead's limbs out of its legs as it goes (sideways from the walk,
capped at two fifths of the walk's speed, so a sprint moves a body and never throws it); it is a cosmetic, each
machine's own, never sent. Untick its `enabled` to let the legs pass through; `reach`, `height`, `push_speed`,
`speed_share` and `lead` tune it live.

## Vaulting and mantling {#vaulting}

Press jump running at a wall that carries a `Vaultable` and the character vaults over it (0.45 to 1.3 m high and up to
0.9 m thick, with room to land beyond) or, when it is higher (up to 2.0 m), thicker or has no room to land, mantles up
onto it. A wall without the component is only jumped, so the level decides what can be crossed: the map's vault course
(west of the room, the orange walls labelled `vault 0.5 m` to `mantle 1.6 m`, and a dark `no vault` wall beside them)
shows each case. The crossing is a path warped to the wall it measured (hand plant on the near edge, feet over the
top, landing clear of the far side), so one clip serves every height; it is stepped from the command like the rest of
the body, so an AI or a server does it the same way, and `CharacterState` keeps it.

To make an obstacle crossable, add a `Vaultable` node under its body (or beside the `Body` of a `ProtoBlock`, as the
course does). Its inspector: `allow_vault`, `allow_mantle`, the faces it may be crossed from, a height or depth
override for a shape the probe misreads, and a clip of its own for the vault or the mantle.

`vault_settings.tres`, with the defaults:

| Group | Settings (default) |
| --- | --- |
| Trigger | press jump, sprint into it, or both (press jump); the speed the automatic one needs (5.5 m/s); the least speed a vault needs, slower mantles (0); the wait after a crossing before the automatic trigger starts another (0.25 s) |
| Detection | how far past the body's front a wall is looked for (0.7 m) plus how far the body goes in 0.15 s; the widest angle off square to the face (35 degrees); the radius of the sphere cast onto the top (0.08 m); the steepest top (30 degrees) |
| Vault | lowest and highest vault (0.45 and 1.3 m); the high clip from 1.0 m; thickest vault (0.9 m); the feet's clearance over the top (0.12 m); the landing past the far face (1.13 m, the clips' own) and the nearest one settled for when that is blocked (0.3 m); the deepest drop beyond (1.2 m); the shortest and longest vault (0.45 and 1.3 s); the share of the speed kept on landing (0.85); what the two vault clips were keyed on (`low_clip`, `high_clip`: `vault_low.tres`, `vault_high.tres`) and how much faster than its own pace a clip may play (1 to 1.15) |
| Mantle | lowest and highest mantle (0.45 and 2.0 m); the high clip from 1.25 m; the time (0.45 s and 0.5 s a metre); when the feet reach the top (0.7 of the time); how far onto the top (0.1 m) |
| Body | aim and fire stop for the crossing (on) |

The clips are on `Animation` (Traversal group): the vault (`Vault_Low`, one hand, under 1.0 m), the high vault
(`Vault_High`, two hands; the pistol is put away for it), the step out of the landing (`Vault_Land`), the mantle
(`ClimbUp_1m`) and the high mantle, and the range of speeds a mantle's clip may be played at (0.5 to 2). A vault is
fitted to the wall measured: it starts at the frame that fits the distance, the hands land on the top at any height
from 0.45 to 1.3 m, and the model stays level while the capsule goes over (the kit's
`docs/engines/godot/third-person/traversal.md`). `tests/gameplay/test_vault_contacts.gd` measures the hands and the
legs on both mannequins. `vault_motion.started(plan)` (the body's `CharacterVault`) says a crossing began.

## Events other nodes connect to

`Character` (and so `Player`) emits `jumped`, `landed(impact_speed)`, `took_hit(amount, source)`,
`health_changed(health)`, `hit_received(record)`, `interacted(target)`, `item_collected(item_id, amount, total)`,
`state_changed(state)`, `teleported`, `aim_changed(aiming)` and `crouch_changed(crouching)`, `prone_changed(down)`,
`died`, `revived` and `fell` (it went below the tuning's fall limit; the character answers by starting again at a spawn
point, and a game that decides where characters start connects its own answer); `Weapon` emits `fired(projectile)` (null
for a hitscan shot or a blow), `hit_scanned(hit)`, `dry_fired`, `ammo_changed(ammo)`, `reload_started(seconds)`,
`reloaded`, `reload_cancelled` and `definition_changed`, the `Loadout` `weapon_changed`, `switch_started` and
`switch_finished`, a `Projectile` `impacted(collider, point, normal)` and a `Target` `shot`, `knocked_down` and
`stood_up`. A shot on a character finds the body part in its path (`HitZones`, eleven parts with a damage multiplier
each) and gives the character a `HitRecord` (`take_hit(record)`): its `Health` node takes the health (`max_value`, 100;
`enabled`) and dies at zero, the ragdoll thrown along the shot from the hit bone; a hit that does not kill makes the hit
part flinch (`HitReaction`; its bones keep their lengths through `RagdollLengths`), and a shot on a lying body pushes
the bone and leaves a mark on it. The record is all a network sends for a hit (`encode()`, about 40 bytes); every peer
makes the rest. `player.hit(amount, source)` is a blow with no point: it takes the health too, stops the character for
the stun time and throws it away from the source.
`player.teleport(spot)` moves it and the camera cuts to it (the camera would otherwise fly there).

## Animation {#animation}

`CharacterAnimation` builds the player's `AnimationTree` in code, when the game starts and when the player scene is open
in the editor (it is a `@tool` script), so the AnimationTree panel shows the graph with no warning. Nothing generated is
saved into a scene file. The body is a state machine: `ground` (a blend space on ground speed: idle, walk, run, sprint),
`crouch` (a blend space of the crouch idle and the crouch walk), `prone` (the template's own prone idle and crawl,
`prone/Prone_Idle` and `prone/Crawl_Fwd` from `assets/animation/prone/`: the crawl replaces the idle over `blend_time`
as soon as the body moves and plays at `ground speed / crawl_clip_speed` (0.618 m/s, its stride), backwards when the
body moves away from the way it faces), `jump`, `fall`, `land`, `push` and the slide's three clips (`slide_start`,
which runs into the `slide` loop, and `slide_exit`, played when a slide ends standing, which runs into `ground`).
Going down plays `prone/Crouch_To_Prone` over the body for the prone tuning's `enter_time`, getting up
`prone/Prone_To_Crouch` for its `exit_time`. Lying, the weapon is put away (its model hidden, the grip off) because the
fists carry the body; aiming brings it back. A model whose body needs prone clips of its own (the male mannequin's,
kit #1090) gets them from the Animation's `prone_libraries`, by the model's scene file; the vault clips come a body the
same way, from `vault_libraries` (kit #1294).

Aiming lying down plays the held weapon's prone aim clips inside the prone state, over the idle and the crawl from
`spine_01` up, blended by the look: the `WeaponDef`'s `prone_aim_clip`, `prone_aim_up_clip` and `prone_aim_down_clip`
(the pistol's are `prone_aim/Prone_Aim_Neutral`, `_Up` and `_Down`), with `prone_aim_angles` the looks the down and up
clips are made for (25 and 20 degrees; past them the pose stays on the clip). While the body lies, the standing grip
and aim layers below have no weight. A shot lying down plays no shot clip: it kicks the look the pose is on by the
Animation's `prone_shot_kick` (7 degrees), which settles over `prone_shot_kick_time` (0.22 s). A weapon whose
`prone_aim_clip` is empty aims lying down with its standing clips. Each body plays the aim clips solved on its own
arms and hands: the scene's `prone_aim` library is `form_female`'s, and the Animation's `prone_aim_libraries` gives
`form_male` its own file, as `prone_libraries` does for the prone clips. The aim layer stops at the down clip's 25
degrees lying down (`ProneTuning.aim_limits`), so the pistol never turns into the floor. A reload lying down plays the weapon's
`prone_reload_clip` (the pistol's is `prone_reload/Prone_Reload_Pistol`) on the reload layer, never the standing
`reload_clip`: the body rolls a little onto its right side, the right arm props on its elbow with the pistol canted
in front of the face, and the left hand fetches the magazine at the belt, pushes it in and takes the pistol again,
at the standing reload's shares, so the `WeaponHold` follows it as it is. Each body plays the reload solved on it
(`prone_reload_libraries`, as the aim's files). A reload with the pistol put away brings
it out for the reload, a body that gets up stops the lying clip, and a weapon with no `prone_reload_clip` shows no
clip lying down. The camera frames it with its
Prone aim group
(`PlayerCamera`: `prone_aim_view`, `prone_aim_distance` 1.8 m, `prone_aim_ahead` 0.55 m, `prone_aim_rise` 0 m,
`prone_aim_shoulder` 0.7 m, `prone_aim_fov` 50 degrees): the view turns about the shoulders, not the hips, and sits
further to the side, so the hands and the pistol show beside the head above the HUD.
Over it is the pistol layer. Off aim and fire the pistol only sits in the right hand: the locomotion clip drives the
arms and the spine (walk, jog, sprint, crouch and jump all swing the arm as they do unarmed) and only the gripping hand
(the wrist, fingers and thumb) takes the grip pose of `Pistol_Idle`. Aiming or firing brings the arm up over
`aim_pose_time` to the aim pose by how far up or down the character looks (`Pistol_Aim_Down`, `Pistol_Aim_Neutral`,
`Pistol_Aim_Up`) on the upper body (the spine, arms, head and fingers; the legs keep the locomotion), and `Pistol_Shoot`
is added to it for each shot (`WeaponDef.shoot_additive`: the clip less its own first frame, so the gun kicks about 16
degrees up from wherever it aims). On top of everything is a one-shot layer for actions: interact and hit play there,
and so does anything else:

```gdscript
$Player/Animation.play_clip(CharacterClips.SWORD_ATTACK)
$Player/Animation.play_clip(CharacterClips.OPEN_CHEST, 1.0)  # taking 1 second
```

`CharacterClips` names every clip (`ual1/` and `ual2/` for the two libraries; the `_Loop` of a looping clip's name is
dropped on import and the clip loops) and lists all 86 in `CharacterClips.ALL`. The clip each state plays is an
inspector setting of `CharacterAnimation`. Both libraries use the Quaternius universal rig, which is both mannequins', so
no retargeting is needed.

**The Weapon group of `CharacterAnimation`** and the held weapon's clips (all read while the game runs; a change, on
the node or on the `WeaponDef`, builds the tree again):

| Setting | Default | What it does |
| --- | --- | --- |
| `carry` | `Hand Only` | How the weapon is carried off aim and fire. `Hand Only`: the arms and the spine follow the locomotion and only the grip bones take the grip pose. `Held Pose`: the grip clip holds the whole upper body, both arms out in front (a weapon at the ready, a rifle). |
| `WeaponDef.grip_clip` | `Pistol_Idle` | The pose the gripping hand takes (and the whole upper body in `Held Pose`). Empty (the fists): none. |
| `WeaponDef.grip_bones` | `hand_r` | The bones that take the grip pose in `Hand Only`, each with every bone below it (the wrist and the fingers). Add `hand_l` for a two-handed weapon; a name the skeleton lacks is ignored. |
| `WeaponDef.aim_clip`, `aim_up_clip`, `aim_down_clip`, `shoot_clips`, `reload_clip` | the `Pistol_*` clips | The aim pose by pitch, the recoil and the reload (a melee blow's clips are the weapon category's `melee_clips`), stretched to the reload's time. A weapon that names no shot clip plays none on a shot. |
| `WeaponDef.shoot_additive` | on (the pistol), off (the fists) | On: the shot's clip is added to the aim as its difference from its own first frame, so the kick rides any pitch; off: it replaces the upper body while it plays. |
| `upper_body_bone` | `spine_01` | Where the aim pose starts: this bone and everything below it. |
| `aim_brace` | on | Holds the upper body's turn on the stance the aim poses were made on while the character aims standing, walking or running (`AimBrace`, a skeleton modifier): the pistol points along the view whatever the legs' clip does to the pelvis. Off, the aim pose turns with that pelvis. |
| `aim_stance` | on | Holds the legs still under a standing aim (`AimStance`): the ground state's idle point blends to the idle clip held on its steadiest frame (the pelvis nearest the middle of its sway) as the arm comes up, so the idle's weight shift no longer sways the pistol (33 mm to each side without it; the muzzle stays within 0.1 mm through 10 s of a held aim, the feet within 2.3 mm while it blends, on the player's and the enemies' bodies). Walking, the blend space has left the idle point, so the gaits are unchanged. Off, the idle plays under the aim. |
| `aim_pitch_range`, `shoot_speed` | 45 deg, 1.6 | How far the character looks up or down for the full aim up and down poses, and the recoil's speed. |
| `shot_hold_time` | 0.2 s | How long the arm stays up after a shot, so a shot fired without aiming (hip fire) shows. The walk and the turn are normal at once; 0 lowers the arm as soon as the buttons are let go. |

The pistol sits in the hand without sinking into the leg or the body in the locomotion, crouch, jump and push clips on
both mannequins: `tests/gameplay/test_pistol_clearance.gd` measures it on the skinned body, and
`tools/carry/measure_clearance.gd` prints the numbers for another grip. If a game changes the grip, run both.

**The hands on the pistol** are closed by `WeaponHold` (`gameplay/weapon/hold/weapon_hold.tscn`, a node of
`character_dressed.tscn`), after the clips: the library's fist is one pose for every weapon and does not fit this one.
It makes three modifiers under the model's `Skeleton3D` and makes them again when the model is replaced. It reads the
pistol layer's weights (`CharacterAnimation.pistol_weights()`) and where the reload clip is (`reload_progress()`), so it
follows the carry, the aim, a reload and a death with no wiring of its own. Lying with a prone aim
(`prone_hold_share()`), its left arm keeps the elbow the clip gives it (`support_keep_elbow`). Through a reload the
left hand is on the
pistol, away with the clip's arm for the new magazine, under the magazine while it goes in, and on the pistol again. The
magazines go with it: the pistol's own `Magazine` drops out of the grip and falls to the floor when the reload's first
sound plays, a new one is in the left hand from the belt (the fingers open, then close on it), comes up the grip's own
line and is the pistol's `Magazine` again once it is in; a reload cut short leaves the pistol whole. The slide stands
back while the pistol is empty and runs forward when the reload's last sound plays. The two hands hold the pistol
together as a two-handed grip is taught: the left hand canted, its fingers over the right hand's and round the front of
the grip, its index finger under the trigger guard, its thumb forward along the frame, and the right thumb on the root
of the left one. The left hand goes on and off the pistol one way, for the aim and the reload alike: its fingers open
where it holds, the opened hand leaves along a line that passes through nothing, and only at the line's far end does the
clip's arm take it; it waits there while the right thumb makes room, and an arm too short for the hand's place (the aim
coming up) backs the hand off along that line. `SupportHandPlan` (`gameplay/weapon/hold/support_hand_plan.gd`) works
that out and names the reload's phases (`HELD`, `LET_GO`, `AWAY`, `REACH`, `INSERT`, `SEATED`, `RETURN`); read
`WeaponHold.left_hand()` for whatever should move with the hand. Held in one hand (`one_handed`, kit #1085) a fourth
modifier turns the body side-on and reaches the right arm out, and the left hand comes in only to reload. Everything
is tuned in its inspector while the game runs:

| Property | Default | What it does |
| --- | --- | --- |
| `grip_pose`, `trigger_pose` | `pistol_grip_pose.tres`, `pistol_trigger_pose.tres` | The right hand on the grip with the index finger along the frame, and the index finger on the trigger, blended in as the character aims. |
| `trigger_way_pose` | `pistol_trigger_way_pose.tres` | Where the index finger is half-way between the frame and the trigger: it goes round by this pose, clear of the left thumb, never straight. |
| `trigger_way` | `pistol_trigger_way.tres` (the male body's in his fit) | The poses the index finger passes through between the frame and the trigger with both hands on the pistol: off the frame to its own side, its last two bones bent there, then into the trigger guard, clear of the guard and the left hand all the way. Written by `tools/hold/solve_pistol_trigger_way.gd`; when it is set, two-handed, `trigger_way_pose` is not used. |
| `thumb_pose` | `pistol_thumb_pose.tres` | The right thumb while the left hand is on the pistol: on the root of the left thumb, which takes its place on the frame. |
| `thumb_way_pose` | `pistol_thumb_way_pose.tres` | Where the right thumb is half-way between the frame and the left thumb's root: lifted clear of the frame's rear edge, which the straight blend passed through. Set by hand. |
| `support_pose` | `pistol_support_pose.tres` | The left hand on the pistol and over the right hand, used while aiming or firing. |
| `support_marker` | `SupportHand` | The weapon's child the left hand's bone is brought to; move the marker in `pistol_held.tscn` and the hand follows. |
| `support_arm`, `support_elbow` | the left arm's three bones, (0.6, 0.6, 0.2) | The bones that reach, and where the elbow points in the model's space. |
| `carry_arm`, `carry_arm_out` | `upperarm_r`, 8 deg | The weapon's arm and how far it is held out from the body while the weapon is carried, so the grip's foot clears the thigh; it goes back as the character aims or reloads. |
| `open_pose`, `support_way` | `pistol_open_pose.tres`, (0.008, -0.03, 0.051) | The left hand's way off the pistol and back onto it: its fingers opened where it holds, and the line the opened hand leaves along, in the weapon's space, to where the clip's arm takes it. Both are solved together. |
| `free_release_time`, `free_return_time` | 0.2 s, 0.12 s | How long the left hand takes off the weapon, and back onto it, for an action that reaches with it and leaves the aim up (`free_hand(seconds)`). Using a door or a lever takes the aim down for its time, which lets the hand go by itself; the rifle's hold (`TwoHandHold`, Free hand group) lets its left hand go for the same reach and takes the gun down in the right hand (`free_pitch` 50 deg, `free_yaw` 0, `free_clearance`, 0.16 s and 0.26 s). |
| `magazine_pose` | `pistol_magazine_pose.tres` | The left hand's fingers while the heel of its palm pushes the magazine in. |
| `magazine_marker` | `MagazineHand` | The weapon's child the left hand's bone is brought to while the magazine goes in. |
| `magazine_approach`, `return_clearance` | (0.034, -0.105, 0), (0, -0.04, 0.04) | In the weapon's space: where the hand and the new magazine start from under the grip (down the grip's own line, the magazine's length and a little; solved), and how far the hand bows out half-way from under the magazine to the far end of `support_way`, round the grip's foot. |
| `reload_leave`, `reload_reach`, `reload_insert`, `reload_return` | (0.02, 0.1), (0.3, 0.4), (0.4, 0.54), (0.71, 0.88) | The shares of the reload clip between which the left hand lets go (opens, leaves along its way, goes to the clip's arm), comes under the magazine, pushes it in and goes back to the pistol: the times of `Pistol_Reload`, to change with the clip. |
| `magazine_part`, `carry_pose`, `carry_open_pose`, `carry_release`, `carry_arrive` | `Pistol/Magazine`, `pistol_carry_pose.tres`, `pistol_carry_open_pose.tres`, solved, solved | The Magazine group: the weapon's magazine (its mesh is the one in the hand and the one that falls), the left fingers closed on the new magazine and opened before they close on it, and the shares of the way in over which they open off it (the grip's foot comes down over them) and over which they go on, opened, to `magazine_pose`. |
| `reload_take`, `reload_drop` | 0.25, 0.2 | The share of the reload clip at which the hand takes the new magazine at the belt, and the one at which the old magazine drops when the weapon definition gives none (its first reload sound does). |
| `drop_speed`, `dropped_life`, `dropped_mask` | 0.5 m/s, 8 s, World and Props | How fast the old magazine leaves the grip down its line (the weapon's own motion is added), how long it lies in the world (one a character), and what it falls onto; it is on no layer, so no shot and no camera meets it. |
| `slide_part`, `slide_travel`, `reload_slide` | `Pistol/Slide`, 0.04 m, 0.85 | The Slide group: the weapon's slide, how far it stands back while the weapon is empty, and the share at which it runs forward when the definition gives none (its last reload sound does). |
| `one_handed` | off (the held `WeaponDef.one_handed`) | Aim and shoot in the right hand alone: the chest side-on, the arm out along the barrel, the left arm on the locomotion clip and a little out, and the left hand on the pistol only for a reload. Switches while the game runs. |
| `one_hand_pose`, `one_hand_way_pose` | `pistol_one_hand_pose.tres`, `pistol_one_hand_way_pose.tres` (the male's in its fit) | One-handed, the right hand's fingers while it aims (the trigger finger on the trigger, the grip fingers round the grip, the thumb forward along the frame) and the trigger finger half-way there. Every body's lands where the female's does on the gun (`tools/hold/fit_one_hand.gd`; only the seat and the knuckles are the body's own). It comes with the aim over the trigger finger's pose and goes for a reload. |
| `shooting_arm`, `side_on`, `one_hand_reach`, `one_hand_elbow`, `one_hand_offset`, `free_arm_out` | the right arm, 35 deg, 0.96, (-0.5, -1, 0), (0, 0, 0), 10 deg | One-handed: the arm that holds the pistol out, how far the chest turns (the head turns back), how straight the arm is (a share of its length), where its elbow points and where the wrist sits from the barrel's line through the shoulder (model space), and how far the free arm is held out. |
| `kick_climb`, `kick_back`, `kick_up`, `kick_time` | 10 deg, 0.05 m, 0.03 m, 0.4 s | One-handed, each shot: the muzzle climbs at the wrist, the wrist comes back (the elbow bends) and up, at the kick's height; it rises in the first 8 percent of `kick_time` and settles by its end, on top of the shot clip. |
| `held_weight`, `aim_weight`, `reload_weight`, `reload_share`, `shot_kick` | from the animation | How far the hold, its aim and a reload are on, and the share of the reload clip played, for a character posed by hand (no `animation` set). |

The ten poses, the two markers, the way and the pistol's seat are solved, and where the solver's pose did not read
as a hand a finger is set by hand in `tools/hold/pistol_authored.json` (angles, laid over the solved hold when it is
written); no number is typed into a pose file. The pistol folder's `README.md` says how to run the solver again for
another model. `tests/gameplay/test_pistol_hold.gd` holds every clip
to 2 mm in and 5 mm off on both mannequins (through the reload the left hand is never more than 2 mm in, at every
hundredth of the clip while it moves and on every update of the live player reloading while it aims), and
`tools/capture/pistol_hold_study.tscn` prints the numbers and films the close-ups. The hold is a pose
worked out on each machine from the aim the game already has; nothing of it goes over a network.

### The slide rack clip {#slide-rack-clip}

`assets/animation/pistol/pistol_rack.glb` holds one clip of GDStudio's own, `Pistol_Rack` (0.93 s): an overhand rack
of the slide, keyed from nothing by `build_pistol_rack.py` on the player's body (`form_female`) because the library's
reload has none. It starts and ends on the pose `Pistol_Reload` ends on. Each body has its own hand on the slide, as
each has its own hold: `gameplay/weapon/hold/pistol_slide_rack.tres` (a `SlideRack`, the female's) lists
`pistol_slide_rack_male.tres` in `fits`, and `SlideRack.fit()` gives the one solved on the model's file. A rack says
where the left hand's bone is in the pistol's space on its way over the slide, how its fingers are closed on the
slide and opened over it, how far the slide travels and at which shares of the clip the hand grips, pulls and lets
go. A reload of an empty pistol ends with it (kit #1337): the character's `RackLayer` plays the clip as the reload
clip ends, and the `WeaponHold` (its `rack`) reaches the hand there with a `HoldArm`, puts the fingers on with a
`HandPoseModifier` (`SlideRack.set_fingers()`) and moves the pistol's `Slide` node from where it stands locked back,
as `tests/fixtures/rack_stage.gd` drives it on a stage. A shot or a switch cuts it short. On both
bodies the hands are within the hold's 2 mm and 5 mm on every frame, the index finger's and the thumb's pads on the
serrations (`tests/gameplay/test_pistol_rack.gd`). The folder's `README.md` has the beats, the numbers, why it is an
overhand rack and how to build it;
`tools/capture/rack_closeups.tscn` films it, and `tools/capture/rack_live.tscn` films it in the running game.

### Vault clips {#vault-clips}

`assets/animation/vault/vault.glb` holds three clips of the template's own, made for the vault (the Universal
Animation Library has none): `Vault_Low` (a one-handed speed vault over about 0.5 to 1.0 m; the right hand stays free
for the pistol), `Vault_High` (both hands, about 1.0 to 1.3 m; no weapon in the hands) and `Vault_Land` (the step
back into the sprint). They are in place like the library's clips, and `vault_clips.json` beside them gives each
clip's reference obstacle, the speed the body is moved at and the times the hand and the feet touch, for the code
that moves the body over an obstacle of another size. No scene uses them yet: add the file to an `AnimationPlayer` as
a library (`vault`) and play `vault/Vault_Low`. `tools/capture/vault_study.tscn` plays them over their reference boxes,
`tests/assets/test_vault_clips.gd` checks them, and the folder's README says how they are rebuilt.

### Fixed library clips {#fixed-clips}

`assets/animation/fixed/fixed.glb` holds three of the library's clips with one arm swung a few degrees clear of the
shin it passed through on the template's bodies: `Slide_Exit`, which the character plays (`slide_exit_clip`),
`Jump_Land`, which it played until the landing became GDStudio's own (`gds/Land_Soft`, with the take-off
`gds/Jump_Start` and the fall `gds/Jump_Fall`: `assets/animation/own/README.md`) and which is now that clip's
stand-in, and `NinjaJump_Land`. Everything else in them is the library's. It also holds
`Sword_Dash` and `Sword_Heavy_Combo`, which the template does not play: their thighs passed through each other as
the body turns, so one leg is turned about the line from its hip to its ankle, which moves the knee and leaves the
foot where the library has it (`CharacterClips.STAND_INS` names the library's own for these too). To play the
library's own clip, set the clip in the inspector to the name `CharacterClips.STAND_INS` gives (`fixed/Jump_Land`
for `land_clip`, `ual2/Slide_Exit`). A body of your own with thicker or longer limbs may cross elsewhere: measure it with
`assets/animation/limb_overlap.py` and add the clip to `assets/animation/fixed/build_fixed_clips.py` (its `README.md`
says how).

### Prone and crawl clips {#prone-clips}

`assets/animation/prone/` holds four clips of GDStudio's own for a character that lies down: `Prone_Idle`,
`Crawl_Fwd`, `Crouch_To_Prone` and `Prone_To_Crouch`, imported as an `AnimationLibrary` like the two libraries above,
one file a body (`prone_form_female.glb` for the template's body, `prone_form_male.glb` for the enemies', `prone.glb`
and `prone_male.glb` for the Quaternius mannequins): a clip that rests limbs on the floor fits one body's skin.
The dressed character's `AnimationPlayer` holds the library as `prone`, `prone_reload.glb` as `prone_reload` (the
pistol's reload lying down, `Prone_Reload_Pistol`, 1.67 s, solved on `form_female`; `prone_reload_male.glb` is
`form_male`'s), and `prone_aim.glb` beside it as `prone_aim`
(solved on `form_female`; `prone_aim_male.glb` is `form_male`'s):
three clips that aim the pistol lying down (`Prone_Aim_Neutral`, `Prone_Aim_Up` at 20 degrees, `Prone_Aim_Down` at 25),
flat behind the pistol with both arms stretched ahead and both hands on it. The crawl covers 0.618 m/s at its own rate
with its elbows and feet planted, the body lies 1.07 m ahead of
and 1.03 m behind the origin and 0.5 m high, and the clips hold no weapon (both hands are on the floor). The arms move
the way people crawl: the forearms point inward and rest on their outer edges, rolled 45 degrees, the hands are
fists near the centre line in front of the head, and each fist in turn plants ahead of the other, with the opposite
leg. The folder's `README.md` has every number, the research
on how people crawl, how the clips are built and how to render them; `tools/capture/prone_clips_tour.tscn` plays
them.

## Licences

The two mannequins, both animation libraries and Phantom Camera are third-party files with a `LICENSE.md` each
(`assets/characters/mannequin/`, `assets/animation/universal/`, `addons/phantom_camera/`): CC0 for the Quaternius files
and MIT for Phantom Camera. Give them a line on the game's Credits screen. The pistol and the rifle are GDStudio's own
(MIT, from Deadnight's build scripts), with a `LICENSE.md` each in `assets/weapons/`. The prone and crawl
clips are GDStudio's own too, on the Quaternius rig (`assets/animation/prone/README.md`), and so are the slide
rack clip (`assets/animation/pistol/LICENSE.md`) and the six rifle clips (`assets/animation/rifle/README.md`): the
low ready, the aim level, up and down, a shot and a reload, played on the upper body under the two-handed hold, the
library `rifle`. The fixed clips (`assets/animation/fixed/`) are five of the library's clips with one arm or one leg
moved, CC0 like the library, with their own `LICENSE.md`.

## Testing it in a browser

`game/tools/web_smoke/touch_smoke.py` drives the web export in a phone-sized browser with real touch events: a drag
turns the camera by the designed angle, the stick moves the character, a tap jumps, the Crouch, Aim and Fire buttons
crouch, aim and shoot, and two fingers at once each do only their own job. Run it under `gds quiet` (the command is in
the file's header). It reads the state the game writes to `window.gdprobe` when the page is opened with `?probe`
(`ui/probe/web_probe.gd`).
