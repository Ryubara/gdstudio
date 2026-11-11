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
| `WeaponDef`, `Weapon`, `WeaponLoadout`, `Projectile`, `Target` | `gameplay/weapon/`, `gameplay/projectile/`, `gameplay/target/` | A weapon is a `WeaponDef` resource (`pistol.tres`, `fists.tres`: every number of a shot, the magazine, reserve and reload, its clips and sounds). A `Weapon` fires the one it holds along the ray its character aims by, the crosshair's for the player (pooled `Projectile` spheres, a hitscan ray or a blow), counts the ammunition, reloads and clicks when empty; a `WeaponLoadout` switches between the slots and the empty hands; a projectile pushes physics bodies and bounces or stops, and a `Target` falls over when it is hit. A definition names its model and muzzle under the `Model` slot, so a game adds a weapon with a `.tres` and a model node. |
| `HitZones`, `HitReaction` | `gameplay/hit_zones/`, `gameplay/character/hit_reaction.gd`, nodes of `character_dressed.tscn` | The body parts a shot can hit (a `HitZone` shape each on a bone: `zone`, `bone`, `offset`, `damage_multiplier`, `enabled`), looked for only when a shot meets the capsule, and how the body answers a hit: `death_push`, `lying_push`, the flinch (`flinch_enabled`, `flinch_push`, `flinch_strength`, `flinch_time`, `flinch_hold`). |
| `Impacts` | `world/world.tscn`, `gameplay/impacts/impacts.tscn` | Where a shot lands: a mark on the body it hit (it rides the body and goes with it), an effect and a sound by the kind of surface. A projectile reports its hit to it (the group `impacts`); `WeaponDef.impacts` and `Projectile.impact_effects` switch it off. Its numbers (how long marks last, how many, their size and material) and one `ImpactSurface` node a surface (`Default`, `Wood`, `Metal`, `Target`) are in the inspector, each with an `EffectDef` (the burst and the sound, played by the `EffectEmitter`); a body names its surface with the metadata `surface` or a group. |
| `EffectEmitter`, `EffectDef` | `world/world.tscn` (`Effects`), `gameplay/effects/` (the scripts: `addons/gds_game/effects/`, synced from the kit) | Plays one-shot effects from one capped pool: an `EffectDef` (a particles scene, a sound, a flash of light, a length) is played at a point or on a node, by the muzzle flash and every bullet impact, and by anything a game adds. The pool is smaller in the web build, lights are limited, an effect frees its slot when it ends, the first frames of the level draw each effect once unseen (`warm_up_on_start`) so the first shot does not stop the web build, and nothing is sent over the network. Its switches and caps are in the inspector. |
| Muzzle flash | `gameplay/weapon/muzzle_flash.tres`, `muzzle_flash.tscn` | A star and a spray of sparks (`CPUParticles3D`) and a light on the pistol's `Muzzle`, pointing out of the barrel. `Weapon.muzzle_flash_enabled`, and the definition's `muzzle_flash` (another `EffectDef` for another weapon) and `muzzle_flash_size`, tune it. |
| `Footsteps` | `gameplay/character/footsteps.tscn` | Plays a step each time a foot of the animated skeleton lands (walk, run, sprint, crouch walk), through three `AudioStreamPlayer3D` nodes on the `SFX` bus. |
| `Crosshair` | `ui/hud/crosshair.tscn` | A small white circle with a thin dark ring at the middle of the screen, drawn by the node itself and shown only while the player aims. |
| `Interactor` | `gameplay/character/interactor.gd` | Finds the nearest usable thing in front: a node of the group `interactable` with an `interact()` method (a `Door` joins when `player_can_use` is on). |
| `CameraZone` | `gameplay/camera_zone/camera_zone.gd` | Hands the view to another Phantom Camera while the player stands in a `TriggerZone`. |
| `PhysicsLayers` | `core/physics_layers/physics_layers.gd`, `project.godot` `[layer_names]` | The seven named layers and the masks: the player is on Characters and meets World and Props (two characters walk through each other, for networking), shots meet characters, props, the level and a dead body's bones, the camera's walls are World and Props, pickups and zones mask what they sense. Tune a body's layers in its scene's Collision group; the names show in the inspector. |
| `TouchControls` | `ui/touch/third_person_touch_controls.tscn` (inherits 3D Blank's `touch_controls.tscn`) | The phone controls: a floating stick, a look drag and buttons that press the game's input actions (Jump and Use from the base; Fire, Aim, Crouch and Prone added here). |
| The rifle | `assets/weapons/rifle/` | An assault rifle model for the weapon work (not yet held or fired): `rifle.glb` and its far level `rifle_far.glb` with the hand sockets (`Grip`, `Support`), `Muzzle`, `Butt` and the `Magazine` and `Bolt` as their own nodes; `rifle.tscn` shows the far level from 10 m. How a character can hold it with the clips the template has is in the folder's README. |
| The mannequin and its clips | `assets/characters/mannequin/`, `assets/animation/universal/` | Quaternius's female and male mannequins (`mannequin_female.glb`, `mannequin_male.glb`) and the Universal Animation Library 1 and 2 (CC0), 86 clips, each with a licence entry. |

## Input

`PlayerInput` (a child of `Player`) reads actions, never devices: `move_left`, `move_right`, `move_forward`,
`move_back`, `jump`, `sprint`,
`walk` (a slow walk), `interact`, `crouch`, `prone`, `aim`, `fire`, `reload`, `next_weapon`,
`previous_weapon`, `toggle_unarmed` and, for the camera, `look_left`, `look_right`, `look_up`,
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
9 m/s, fading by 1 m/s each second). Aim and fire work while sliding. Another slide waits 0.3 s.

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
| Shooting | shooting allowed (on) |
| Slide jump | slide jump (on), its height share (0.85), boost (0), most speed (9 m/s) and air drag (1 m/s²) |

The character lies down only on the ground and gets up through crouch, only when a crouched body fits above it: under
a gap only a lying body fits under (0.8 m, say), letting go of prone keeps it down until it crawls out.

Vaulting and mantling have their own resource, `gameplay/character/vault_settings.tres` (the `Character`'s
`vault_settings`, in its Traversal group; empty turns them off), described in [Vaulting and mantling](#vaulting).

Every number is read while the game runs, so you can change it in the remote inspector and see it at once; the capsule,
the steepest slope and the floor snap are applied again whenever the resource changes. The `Interactor`'s half angle
(how far from straight ahead still counts as in front, 75 degrees) is on that node.

A `PhysicsProp` has a `push_speed` of its own: the cubes of the map are 60 kg, grippy (friction 0.5) and pushed at 1.2
m/s, so the character (15 percent faster than the cube, to stay against it) walks slowly into them and the push clip
plays for as long as it keeps going (0 leaves a prop to the character's push strength, as the spheres are). The
pistol's definition (`gameplay/weapon/pistol.tres`) holds the shot's numbers: fire rate (4 a second), semi or full
automatic, spread, damage (34 before the hit zone's multiplier), aim range, the push it gives a body (40 N·s), the
magazine (12), the reserve (36, at most 96, filled by a `Pickup` of `pistol_ammo`), the reload (1.6 s, by itself when
the magazine is empty), the switch (0.2 s down, 0.25 s up), the projectile's speed (45 m/s), size, colour, gravity (0,
so it flies straight at the crosshair), lifetime and bounces, the clips and the sounds (five shots at a small random
pitch, two empty clicks, the reload's three steps, the draw). The fists (`fists.tres`) throw a jab and a cross 1.1 m,
2.5 a second, with no ammunition. The `Weapon` node keeps the rest: `no_muzzle_offset` (where a shot starts when the
weapon has no `muzzle`, as on a character with no model: beside its `shooter`, this far off the aim ray),
`projectile_cap` (24 in flight) and `self_ticking` (on: the weapon counts its own cooldown and reload; the `Character`
turns it off and counts them in its step); its `ShotSound`, `EmptySound`, `ReloadSound` and `DrawSound` nodes hold the
volume, bus and voices. The `Loadout` lists the slots (the pistol) and the empty hands (the fists).

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
aiming, with `zoom_when_firing` to turn it off, and a Shot kick: `shot_kick_amplitude` in degrees, off at 0, and
`shot_kick_duration`). Any other shake in the game is one line, `CameraShake.shake(preset, at)`, with a `ShakePreset`
from `core/camera_shake/presets/`; `CameraShake.strength` (0 to 1) is the player's setting for all of it. The zoom
follows the buttons: it starts back out on the next frame after aim and fire are let go, and so does the character:
its walk speed, turn and clips are the normal ones at once and only the arm lowers over the aim pose time (a shot
needs the arm half up, so a tap shorter than about 75 ms shoots nothing).

**Where each framing value lives.** The distance is on `PlayerCamera`. The over-the-shoulder view is the `Camera` node's
own **H Offset** and **V Offset** (they shift the view without moving the camera or its wall cast), and `PlayerCamera`
sets them from its Shoulder group: `shoulder` (left, center, right; Q or a click of the right stick swaps left and
right), `shoulder_offset` (0.5 m to the side), `vertical_offset` and `shoulder_time` (the seconds a swap takes, 0.3; 0
swaps at once). A swap made while aiming keeps what the crosshair is on under it (Shoulder swap subgroup; a swap while
walking or sprinting only slides the view, so the run keeps its way, unless `keep_aim_when_not_aiming`, off, is on):
`keep_aim_on_swap` (on) finds
the point under the crosshair when the swap starts (what the weapon would hit, or the ray's end at `aim_point_range`,
100 m, when nothing is there; never nearer than `aim_point_min_distance`, 2 m, past the arm, on `aim_point_mask`) and
turns the view inward as it slides so the point stays put, so a shot fired mid-swap goes there; `aim_shoulder_time`
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
| Vault | lowest and highest vault (0.45 and 1.3 m); the high clip from 1.0 m; thickest vault (0.9 m); the feet's clearance over the top (0.12 m); the landing past the far face (0.3 m); the deepest drop beyond (1.2 m); the least crossing speed (4 m/s), shortest and longest vault (0.45 and 0.9 s); the share of the speed kept on landing (0.85); the hand plant and the clear of the far edge as shares of the clip (0.3 and 0.7) |
| Mantle | lowest and highest mantle (0.45 and 2.0 m); the high clip from 1.25 m; the time (0.45 s and 0.5 s a metre); when the feet reach the top (0.7 of the time); how far onto the top (0.1 m) |
| Body | aim and fire stop for the crossing (on) |

The clips are on `Animation` (Traversal group): the vault (a placeholder, `NinjaJump_Start`, until the template's own
vault clips land), the high vault, the mantle (`ClimbUp_1m`) and the high mantle, and the range of speeds a clip may be
played at (0.5 to 2). `vault_motion.started(plan)` (the body's `CharacterVault`) says a crossing began.

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
part flinch (`HitReaction`), and a shot on a lying body pushes the bone and leaves a mark on it. The record is all a
network sends for a hit (`encode()`, about 40 bytes); every peer makes the rest. `player.hit(amount, source)` is a blow
with no point: it takes the health too, stops the character for the stun time and throws it away from the source.
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
kit #1090) gets them from the Animation's `prone_libraries`, by the model's scene file.
Over it is the pistol layer. Off aim and fire the pistol only sits in the right hand: the locomotion clip drives the
arms and the spine (walk, jog, sprint, crouch and jump all swing the arm as they do unarmed) and only the gripping hand
(the wrist, fingers and thumb) takes the grip pose of `Pistol_Idle`. Aiming or firing brings the arm up over
`aim_pose_time` to the aim pose by how far up or down the character looks (`Pistol_Aim_Down`, `Pistol_Aim_Neutral`,
`Pistol_Aim_Up`) on the upper body (the spine, arms, head and fingers; the legs keep the locomotion), and `Pistol_Shoot`
plays for each shot. On top of everything is a one-shot layer for actions: interact and hit play there, and so does
anything else:

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
| `WeaponDef.aim_clip`, `aim_up_clip`, `aim_down_clip`, `shoot_clips`, `reload_clip` | the `Pistol_*` clips | The aim pose by pitch, the recoil (the fists: `Punch_Jab` and `Punch_Cross` in turn) and the reload, stretched to the reload's time. |
| `upper_body_bone` | `spine_01` | Where the aim pose starts: this bone and everything below it. |
| `aim_pitch_range`, `shoot_speed` | 45 deg, 1.6 | How far the character looks up or down for the full aim up and down poses, and the recoil's speed. |
| `shot_hold_time` | 0.2 s | How long the arm stays up after a shot, so a shot fired without aiming (hip fire) shows. The walk and the turn are normal at once; 0 lowers the arm as soon as the buttons are let go. |

The pistol sits in the hand without sinking into the leg or the body in the locomotion, crouch, jump and push clips on
both mannequins: `tests/gameplay/test_pistol_clearance.gd` measures it on the skinned body, and
`tools/carry/measure_clearance.gd` prints the numbers for another grip. If a game changes the grip, run both.

**The hands on the pistol** are closed by `WeaponHold` (`gameplay/weapon/hold/weapon_hold.tscn`, a node of
`character_dressed.tscn`), after the clips: the library's fist is one pose for every weapon and does not fit this one.
It makes three modifiers under the model's `Skeleton3D` and makes them again when the model is replaced. It reads the
pistol layer's weights (`CharacterAnimation.pistol_weights()`) and where the reload clip is (`reload_progress()`), so
it follows the carry, the aim, a reload and a death with no wiring of its own. Through a reload the left hand is on
the pistol, away with the clip's arm for the new magazine, under the magazine while it goes in, and on the pistol
again; the pistol's `Magazine` does not move yet. The two hands hold the pistol together as a two-handed grip is
taught: the left hand canted, its fingers over the right hand's and round the front of the grip, its index finger
under the trigger guard, its thumb forward along the frame, and the right thumb on the root of the left one. The left
hand goes on and off the pistol one way, for the aim and
the reload alike: its fingers open where it holds, the opened hand leaves along a line that passes through nothing,
and only at the line's far end does the clip's arm take it; it waits there while the right thumb makes room, and an
arm too short for the hand's place (the aim coming up) backs the hand off along that line. `SupportHandPlan`
(`gameplay/weapon/hold/support_hand_plan.gd`) works that out and names the reload's phases (`HELD`, `LET_GO`,
`AWAY`, `REACH`, `INSERT`, `SEATED`, `RETURN`); read `WeaponHold.left_hand()` for whatever should move with the
hand. Everything is tuned in its inspector while the game runs:

| Property | Default | What it does |
| --- | --- | --- |
| `grip_pose`, `trigger_pose` | `pistol_grip_pose.tres`, `pistol_trigger_pose.tres` | The right hand on the grip with the index finger along the frame, and the index finger on the trigger, blended in as the character aims. |
| `trigger_way_pose` | `pistol_trigger_way_pose.tres` | Where the index finger is half-way between the frame and the trigger: it goes round by this pose, clear of the left thumb, never straight. |
| `thumb_pose` | `pistol_thumb_pose.tres` | The right thumb while the left hand is on the pistol: on the root of the left thumb, which takes its place on the frame. |
| `support_pose` | `pistol_support_pose.tres` | The left hand on the pistol and over the right hand, used while aiming or firing. |
| `support_marker` | `SupportHand` | The weapon's child the left hand's bone is brought to; move the marker in `pistol_held.tscn` and the hand follows. |
| `support_arm`, `support_elbow` | the left arm's three bones, (0.6, 0.6, 0.2) | The bones that reach, and where the elbow points in the model's space. |
| `carry_arm`, `carry_arm_out` | `upperarm_r`, 8 deg | The weapon's arm and how far it is held out from the body while the weapon is carried, so the grip's foot clears the thigh; it goes back as the character aims or reloads. |
| `open_pose`, `support_way` | `pistol_open_pose.tres`, (0.019, -0.039, 0.042) | The left hand's way off the pistol and back onto it: its fingers opened where it holds, and the line the opened hand leaves along, in the weapon's space, to where the clip's arm takes it. Both are solved together. |
| `magazine_pose` | `pistol_magazine_pose.tres` | The left hand's fingers while the heel of its palm pushes the magazine in. |
| `magazine_marker` | `MagazineHand` | The weapon's child the left hand's bone is brought to while the magazine goes in. |
| `magazine_approach`, `return_clearance` | (0, -0.1, 0), (0, -0.04, 0.04) | In the weapon's space: where the hand starts from under the magazine (a magazine's length down the grip), and how far it bows out half-way from under the magazine to the far end of `support_way`, round the grip's foot. |
| `reload_leave`, `reload_reach`, `reload_insert`, `reload_return` | (0.02, 0.1), (0.3, 0.4), (0.4, 0.54), (0.71, 0.88) | The shares of the reload clip between which the left hand lets go (opens, leaves along its way, goes to the clip's arm), comes under the magazine, pushes it in and goes back to the pistol: the times of `Pistol_Reload`, to change with the clip. |
| `held_weight`, `aim_weight`, `reload_weight`, `reload_share` | from the animation | How far the hold, its aim and a reload are on, and the share of the reload clip played, for a character posed by hand (no `animation` set). |

The seven poses, the two markers, the way and the pistol's seat are solved, never typed: the pistol folder's
`README.md` says how to run the solver again for another model. `tests/gameplay/test_pistol_hold.gd` holds every clip
to 2 mm in and 5 mm off on both mannequins (through the reload the left hand is never more than 2 mm in, at every
hundredth of the clip while it moves and on every update of the live player reloading while it aims), and
`tools/capture/pistol_hold_study.tscn` prints the numbers and films the close-ups. The hold is a pose
worked out on each machine from the aim the game already has; nothing of it goes over a network.

### Prone and crawl clips {#prone-clips}

`assets/animation/prone/prone.glb` holds four clips of GDStudio's own for a character that lies down: `Prone_Idle`,
`Crawl_Fwd`, `Crouch_To_Prone` and `Prone_To_Crouch`, imported as an `AnimationLibrary` like the two libraries above.
The player does not play them yet (the prone stance is kit #1012); add the library to an `AnimationPlayer` as `prone`
to use them. The crawl covers 0.618 m/s at its own rate with its elbows and feet planted, the body lies 1.07 m ahead of
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
clips are GDStudio's own too, on the Quaternius rig (`assets/animation/prone/README.md`).

## Testing it in a browser

`game/tools/web_smoke/touch_smoke.py` drives the web export in a phone-sized browser with real touch events: a drag
turns the camera by the designed angle, the stick moves the character, a tap jumps, the Crouch, Aim and Fire buttons
crouch, aim and shoot, and two fingers at once each do only their own job. Run it under `gds quiet` (the command is in
the file's header). It reads the state the game writes to `window.gdprobe` when the page is opened with `?probe`
(`ui/probe/web_probe.gd`).
