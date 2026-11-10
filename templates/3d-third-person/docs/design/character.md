# The character

What the template's character does, what to tune and where to change what it plays. The scenes are in
`game/gameplay/player/`; the controller, the camera, the animation and the touch controls are separate parts that
talk through signals and input actions, so each can be replaced alone.

## The parts

| Part | Where | What it does |
| --- | --- | --- |
| `Player` | `gameplay/player/player.tscn` | A `CharacterBody3D`: walks, runs, sprints, crouches, jumps, climbs low steps, rides a `MovingPlatform`, pushes a `PhysicsProp`, opens a `Door`, collects a `Pickup`, aims and shoots. Says what happens in signals. |
| `PlayerTuning` | `gameplay/player/player_tuning.tres` | Every number a developer tunes, grouped, with ranges and units (below). A copy of the file gives a second feel. |
| `PlayerCamera` | `main.tscn`, `gameplay/player/player_camera.gd` | A thin wrapper that sets the follow, orbit and wall settings on a Phantom Camera (`FollowCamera`) and turns it to the orbit input. Tune this node, never `Camera`. |
| `Ragdoll` | `gameplay/player/player_ragdoll.gd`, a node of `player.tscn` | Makes physical bones on the skeleton of the `Model` slot, from the model's own bones, and holds the skeleton while the player is dead. Nothing it makes is saved in a scene; its exports are the body's mass, damping, joint range, layers and get-up time. |
| `PlayerAnimation` | `gameplay/player/player_animation.gd` | Builds an `AnimationTree` from the player's state and plays any other clip on request. |
| `Weapon`, `Projectile`, `Target` | `gameplay/weapon/`, `gameplay/projectile/`, `gameplay/target/` | The pistol's shots: a `Weapon` fires `Projectile` spheres from a muzzle marker toward the crosshair (every number of a shot is its inspector's), a projectile pushes physics bodies and bounces or stops, and a `Target` falls over when it is hit. They know nothing of the pistol model, so a game reuses them with another one. |
| `Impacts` | `main.tscn`, `gameplay/impacts/impacts.tscn` | Where a shot lands: a mark on the body it hit (it rides the body and goes with it), an effect and a sound by the kind of surface. A projectile reports its hit to it (the group `impacts`); `Weapon.impacts` and `Projectile.impact_effects` switch it off. Its numbers (how long marks last, how many, their size and material) and one `ImpactSurface` node a surface (`Default`, `Wood`, `Metal`, `Target`) are in the inspector, each with an `EffectDef` (the burst and the sound, played by the `EffectEmitter`); a body names its surface with the metadata `surface` or a group. |
| `EffectEmitter`, `EffectDef` | `main.tscn` (`Effects`), `gameplay/effects/` | Plays one-shot effects from one capped pool: an `EffectDef` (a particles scene, a sound, a flash of light, a length) is played at a point or on a node, by the muzzle flash and every bullet impact, and by anything a game adds. The pool is smaller in the web build, lights are limited, an effect frees its slot when it ends, the first frames of the level draw each effect once unseen (`warm_up_on_start`) so the first shot does not stop the web build, and nothing is sent over the network. Its switches and caps are in the inspector. |
| Muzzle flash | `gameplay/weapon/muzzle_flash.tres`, `muzzle_flash.tscn` | A star and a spray of sparks (`CPUParticles3D`) and a light on the pistol's `Muzzle`, pointing out of the barrel. `Weapon.muzzle_flash_enabled`, `muzzle_flash` (another `EffectDef` for another weapon) and `muzzle_flash_size` tune it. |
| `Footsteps` | `gameplay/player/footsteps.tscn` | Plays a step each time a foot of the animated skeleton lands (walk, run, sprint, crouch walk), through three `AudioStreamPlayer3D` nodes on the `SFX` bus. |
| `Crosshair` | `ui/hud/crosshair.tscn` | A small white circle with a thin dark ring at the middle of the screen, drawn by the node itself and shown only while the player aims. |
| `Interactor` | `gameplay/player/interactor.gd` | Finds the nearest usable thing in front: a node of the group `interactable` with an `interact()` method (a `Door` joins when `player_can_use` is on). |
| `CameraZone` | `gameplay/camera_zone/camera_zone.gd` | Hands the view to another Phantom Camera while the player stands in a `TriggerZone`. |
| `TouchControls` | `ui/touch/third_person_touch_controls.tscn` (inherits 3D Blank's `touch_controls.tscn`) | The phone controls: a floating stick, a look drag and buttons that press the game's input actions (Jump and Use from the base; Fire, Aim and Crouch added here). |
| The rifle | `assets/weapons/rifle/` | An assault rifle model for the weapon work (not yet held or fired): `rifle.glb` and its far level `rifle_far.glb` with the hand sockets (`Grip`, `Support`), `Muzzle`, `Butt` and the `Magazine` and `Bolt` as their own nodes; `rifle.tscn` shows the far level from 10 m. How a character can hold it with the clips the template has is in the folder's README. |
| The mannequin and its clips | `assets/characters/mannequin/`, `assets/animation/universal/` | Quaternius's female and male mannequins (`mannequin_female.glb`, `mannequin_male.glb`) and the Universal Animation Library 1 and 2 (CC0), 86 clips, each with a licence entry. |

## Input

The player reads actions, never devices: `move_left`, `move_right`, `move_forward`, `move_back`, `jump`, `sprint`,
`walk` (a slow walk), `interact`, `crouch`, `aim`, `fire` and, for the camera, `look_left`, `look_right`, `look_up`,
`look_down` and `shoulder_swap`. Each has a key and, where it makes sense, a pad binding for any device; the touch
layer presses the same actions. Rebind them in Project Settings > Input Map.

| Action | Keyboard and mouse | Pad | Touch |
| --- | --- | --- | --- |
| Move | WASD or arrows | left stick | the left thumb: a stick appears where it lands |
| Look | mouse (click the game to capture it; Esc lets go) | right stick | drag on the right half of the screen |
| Jump | Space | A | the Jump button |
| Sprint | Shift | left bumper | push the stick out to its outer ring |
| Walk | X (held) | a gentle push on the stick | a gentle push on the stick |
| Interact | E | X | the Use button |
| Crouch | C or Ctrl (held; a toggle in the tuning) | B | the Crouch button |
| Aim | right mouse button (held) | left trigger | the Aim button |
| Fire | left mouse button | right trigger | the Fire button (it aims too) |
| Swap shoulder | Q | right stick click | none |
| Die and get up (a testing aid) | Y (`Player`'s `ragdoll_key`; None turns it off) | none | none |

The character moves toward where the camera looks and turns to face its movement; while it aims it faces where the
camera looks instead, however it walks (the clips only walk forward, so a sidestep slides).

## What to tune {#tuning}

Open `gameplay/player/player_tuning.tres` in the inspector. The groups, with the defaults:

| Group | Settings (default) |
| --- | --- |
| Ground | walk speed (1.7 m/s), run speed (4.0), sprint speed (6.5), acceleration (28), deceleration (36), turn speed (12 rad/s) |
| Jump | jump height (1.25 m), rise time (0.4 s; height and time give gravity), fall gravity scale (1.35), short-jump scale (0.5), coyote time (0.12 s), jump buffer (0.14 s) |
| Air | air control (0.45) |
| Slopes and steps | max slope (48 degrees), step height (0.32 m), snap length (0.35 m) |
| Crouch | crouch height (1.1 m), crouch speed (1.5 m/s), time to crouch and stand (0.2 s), toggle or hold (hold), the camera target's height standing (1.55 m) and crouched (0.9 m) |
| Aim | the share of the walk kept while aiming (0.6), turn speed to the camera (18 rad/s), the time the arm takes to come up and go down (0.15 s) |
| Pushing | push strength (0.85), push mass (40 kg) |
| Actions | interact time and reach, hit stun, knockback, the landing speed that plays the landing clip, how long the landing lasts (0.3 s), the speed under which it counts as standing (0.15 m/s) |
| Body | capsule radius (0.34 m) and height (1.8 m) |
| Safety | the height below which it starts again at its spawn point (-25 m) |

Every number is read while the game runs, so you can change it in the remote inspector and see it at once; the capsule,
the steepest slope and the floor snap are applied again whenever the resource changes. The `Interactor`'s half angle
(how far from straight ahead still counts as in front, 75 degrees) is on that node.

A `PhysicsProp` has a `push_speed` of its own: the cubes of the map are 60 kg, grippy (friction 0.5) and pushed at 1.2
m/s, so the character (15 percent faster than the cube, to stay against it) walks slowly into them and the push clip
plays for as long as it keeps going (0 leaves a prop to the character's push strength, as the spheres are). The `Weapon`
(a child of `Player`) holds the shot's numbers: fire rate, semi or full automatic, spread, aim range, the projectile's
speed (45 m/s), size, gravity (0, so it flies straight at the crosshair), lifetime, the push it gives a body (40 N·s)
and how many times it bounces. The sound of a shot is its `ShotSound` node: five pistol shots at a small random pitch
and volume spread, three voices; a game's own shot is another `stream` there.

The sample map is built for these numbers (blocks 1 m apart in height, twelve steps of 0.25 m, a 14 degree ramp): a test
fails when a tuning breaks it, which tells you which part of the map to rebuild.

The camera's settings are all on the `PlayerCamera` node, so you never open the Phantom Camera node: the nodes it
works with (Nodes), distance (1.7 m), the arm's offset (`offset`, in world axes; it moves the wall cast, so keep it near
zero sideways), field of view, near and far clip and start pitch (Framing), the **Shoulder** group, damping (Follow),
mouse, stick and pitch limits (Orbit), the priority and the blend back from a `CameraZone`'s camera (Blending), the wall
mask, shape and margin (Walls), and three views that blend on top of the framing: Sprint (the field of view and distance
added at a full sprint, the zoom speed, and a shake with its amplitude in degrees, frequency and blend speed, off at 0),
Aim (the distance, the field of view and the speeds in and out, and `aim_shifts_shoulder`, off) and Fire (the same for a
shot fired without aiming, with `zoom_when_firing` to turn it off). The zoom follows the buttons: it starts back out on
the next frame after aim and fire are let go, and so does the character: its walk speed, turn and clips are the
normal ones at once and only the arm lowers over the aim pose time (a shot needs the arm half up, so a tap shorter than
about 75 ms shoots nothing).

**Where each framing value lives.** The distance is on `PlayerCamera`. The over-the-shoulder view is the `Camera` node's
own **H Offset** and **V Offset** (they shift the view without moving the camera or its wall cast), and `PlayerCamera`
sets them from its Shoulder group: `shoulder` (left, center, right; Q or a click of the right stick swaps left and
right), `shoulder_offset` (0.5 m to the side), `vertical_offset` and `shoulder_time` (the seconds a swap takes). Tune
the shoulder there, in the editor or in the remote inspector while the game runs; nothing else writes those two values
(the Phantom Camera host copies its lens resource onto `Camera` whenever it changes, so `PlayerCamera` keeps the
resource equal to them). With `aim_shifts_shoulder` on, aiming also moves the view to `aim_shoulder`. The settings are
applied to the `FollowCamera` Phantom Camera when the game starts and again each time one changes, and the node is a
`@tool` script, so changing the distance, the field of view or the shoulder in the editor moves the camera in the
viewport. `Camera` renders and `PhantomCameraHost` copies the active Phantom Camera onto it, so a change to `Camera`'s
field of view is overwritten: tune `PlayerCamera`. Anything else about it (noise, tweens, dead zones) is that node's own
inspector, and the addon's docs are at <https://phantom-camera.dev>.

The touch layer is a scene you arrange in the 2D editor (`ui/touch/third_person_touch_controls.tscn`, which inherits
3D Blank's `touch_controls.tscn` and adds the Fire, Aim and Crouch buttons): drag the `TouchStick` to
move where the stick waits, drag or resize the buttons under `SafeArea/Buttons` (instance `touch_button.tscn` for a new
one and set its action and word), resize the `MoveZone` and `LookZone` panels that decide which finger does what. Its
numbers are on `TouchControls` in `main.tscn`: when it shows, the stick's radius, dead zone and sprint ring, the look
sensitivity and smoothing, the opacity and the margin from the screen edge.

## Dying and the ragdoll {#ragdoll}

`player.die()` makes the character limp: the animation stops, the capsule turns off, every gameplay input is ignored (the
camera still orbits, and follows the hips), and the body falls as a ragdoll keeping the momentum it had.
`player.revive()` gets it up where it lies, facing the way its chest faces, and the pose blends back to the animation.
Ticking `ragdoll` on `Player` in the inspector (also while the game runs, in the remote inspector) or pressing Y does the
same; `teleport()` and `respawn()` get it up at once. The physics engine is Jolt (`project.godot`): the ragdoll's joints
are stable there and were not on Godot Physics. The prototype level has a ramp and a ledge in the south (`RagdollLedge`)
to run off. The way it is built and tuned is in the kit's `docs/engines/godot/ragdoll.md`.

## Events other nodes connect to

`Player` emits `jumped`, `landed(impact_speed)`, `took_hit(amount, source)`, `interacted(target)`,
`item_collected(item_id, amount, total)`, `state_changed(state)`, `teleported`, `aim_changed(aiming)` and
`crouch_changed(crouching)`, `died` and `revived`; `Weapon` emits `fired(projectile)`, a `Projectile`
`impacted(collider, point, normal)` and a `Target` `shot`, `knocked_down` and `stood_up`. A hit comes from calling
`player.hit(amount, source)`; the character stops for the stun time and is thrown away from the source.
`player.teleport(spot)` moves it and the camera cuts to it (the camera would otherwise fly there).

## Animation {#animation}

`PlayerAnimation` builds the player's `AnimationTree` in code, when the game starts and when the player scene is open in
the editor (it is a `@tool` script), so the AnimationTree panel shows the graph with no warning. Nothing generated is
saved into a scene file. The body is a state machine: `ground` (a blend space
on ground speed: idle, walk, run, sprint), `crouch` (a blend space of the crouch idle and the crouch walk), `jump`,
`fall`, `land` and `push`. Over it is the pistol layer. Off aim and fire the pistol only sits in the right hand: the
locomotion clip drives the arms and the spine (walk, jog, sprint, crouch and jump all swing the arm as they do
unarmed) and only the gripping hand (the wrist, fingers and thumb) takes the grip pose of `Pistol_Idle`. Aiming or
firing brings the arm up over `aim_pose_time` to the aim pose by the camera's pitch (`Pistol_Aim_Down`,
`Pistol_Aim_Neutral`, `Pistol_Aim_Up`) on the upper body (the spine, arms, head and fingers; the legs keep the
locomotion), and `Pistol_Shoot` plays for each shot. On top of everything is a one-shot layer for actions: interact and
hit play there, and so does anything else:

```gdscript
$Player/Animation.play_clip(CharacterClips.SWORD_ATTACK)
$Player/Animation.play_clip(CharacterClips.OPEN_CHEST, 1.0)  # taking 1 second
```

`CharacterClips` names every clip (`ual1/` and `ual2/` for the two libraries; the `_Loop` of a looping clip's name is
dropped on import and the clip loops) and lists all 86 in `CharacterClips.ALL`. The clip each state plays is an
inspector setting of `PlayerAnimation`. Both libraries use the Quaternius universal rig, which is both mannequins', so
no retargeting is needed.

**The Pistol group of `PlayerAnimation`** (all read while the game runs; a change builds the tree again):

| Setting | Default | What it does |
| --- | --- | --- |
| `carry` | `Hand Only` | How the weapon is carried off aim and fire. `Hand Only`: the arms and the spine follow the locomotion and only the grip bones take the grip pose. `Held Pose`: the grip clip holds the whole upper body, both arms out in front (a weapon at the ready, a rifle). |
| `grip_clip` | `Pistol_Idle` | The pose the gripping hand takes (and the whole upper body in `Held Pose`). |
| `grip_bones` | `hand_r` | The bones that take the grip pose in `Hand Only`, each with every bone below it (the wrist and the fingers). Add `hand_l` for a two-handed weapon; a name the skeleton lacks is ignored. |
| `aim_clip`, `aim_up_clip`, `aim_down_clip`, `shoot_clip` | the `Pistol_*` clips | The aim pose by pitch, and the recoil. |
| `upper_body_bone` | `spine_01` | Where the aim pose starts: this bone and everything below it. |
| `aim_pitch_range`, `shoot_speed` | 45 deg, 1.6 | The camera pitch of the full aim up and down poses, and the recoil's speed. |
| `shot_hold_time` | 0.2 s | How long the arm stays up after a shot, so a shot fired without aiming (hip fire) shows. The walk and the turn are normal at once; 0 lowers the arm as soon as the buttons are let go. |

The pistol sits in the hand without sinking into the leg or the body in the locomotion, crouch, jump and push clips on
both mannequins: `tests/gameplay/test_pistol_clearance.gd` measures it on the skinned body, and
`tools/carry/measure_clearance.gd` prints the numbers for another grip. If a game changes the grip, run both.

## Licences

The two mannequins, both animation libraries and Phantom Camera are third-party files with a `LICENSE.md` each
(`assets/characters/mannequin/`, `assets/animation/universal/`, `addons/phantom_camera/`): CC0 for the Quaternius files
and MIT for Phantom Camera. Give them a line on the game's Credits screen. The pistol and the rifle are GDStudio's own
(MIT, from Deadnight's build scripts), with a `LICENSE.md` each in `assets/weapons/`.

## Testing it in a browser

`game/tools/web_smoke/touch_smoke.py` drives the web export in a phone-sized browser with real touch events: a drag
turns the camera by the designed angle, the stick moves the character, a tap jumps, the Crouch, Aim and Fire buttons
crouch, aim and shoot, and two fingers at once each do only their own job. Run it under `gds quiet` (the command is in
the file's header). It reads the state the game writes to `window.gdprobe` when the page is opened with `?probe`
(`ui/probe/web_probe.gd`).
