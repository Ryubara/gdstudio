# The character

What the template's character does, what to tune and where to change what it plays. The scenes are in
`game/gameplay/player/`; the controller, the camera, the animation and the touch controls are separate parts that
talk through signals and input actions, so each can be replaced alone.

## The parts

| Part | Where | What it does |
| --- | --- | --- |
| `Player` | `gameplay/player/player.tscn` | A `CharacterBody3D`: walks, runs, sprints, jumps, climbs low steps, rides a `MovingPlatform`, pushes a `PhysicsProp`, opens a `Door`, collects a `Pickup`. Says what happens in signals. |
| `PlayerTuning` | `gameplay/player/player_tuning.tres` | Every number a developer tunes, grouped, with ranges and units (below). A copy of the file gives a second feel. |
| `PlayerCamera` | `main.tscn`, `gameplay/player/player_camera.gd` | A thin wrapper that sets the follow, orbit and wall settings on a Phantom Camera (`FollowCamera`) and turns it to the orbit input. Tune this node, never `Camera`. |
| `PlayerAnimation` | `gameplay/player/player_animation.gd` | Builds an `AnimationTree` from the player's state and plays any other clip on request. |
| `Interactor` | `gameplay/player/interactor.gd` | Finds the nearest usable thing in front: a node of the group `interactable` with an `interact()` method (a `Door` joins when `player_can_use` is on). |
| `CameraZone` | `gameplay/camera_zone/camera_zone.gd` | Hands the view to another Phantom Camera while the player stands in a `TriggerZone`. |
| `TouchControls` | `ui/touch/touch_controls.tscn` (3D Blank) | The phone controls: a floating stick, a look drag and buttons that press the game's input actions. |
| The mannequin and its clips | `assets/characters/mannequin/`, `assets/animation/universal/` | Quaternius's mannequin and the Universal Animation Library 1 and 2 (CC0), 86 clips, each with a licence entry. |

## Input

The player reads actions, never devices: `move_left`, `move_right`, `move_forward`, `move_back`, `jump`, `sprint`,
`walk` (a slow walk), `interact` and, for the camera, `look_left`, `look_right`, `look_up`, `look_down`. Each has a key
and, where it makes sense, a pad binding for any device; the touch layer presses the same actions. Rebind them in
Project Settings > Input Map.

| Action | Keyboard and mouse | Pad | Touch |
| --- | --- | --- | --- |
| Move | WASD or arrows | left stick | the left thumb: a stick appears where it lands |
| Look | mouse (click the game to capture it; Esc lets go) | right stick | drag on the right half of the screen |
| Jump | Space | A | the Jump button |
| Sprint | Shift | left bumper | push the stick out to its outer ring |
| Walk | X (held) | a gentle push on the stick | a gentle push on the stick |
| Interact | E | X | the Use button |

The character moves toward where the camera looks and turns to face its movement.

## What to tune {#tuning}

Open `gameplay/player/player_tuning.tres` in the inspector. The groups, with the defaults:

| Group | Settings (default) |
| --- | --- |
| Ground | walk speed (1.7 m/s), run speed (4.0), sprint speed (6.5), acceleration (28), deceleration (36), turn speed (12 rad/s) |
| Jump | jump height (1.25 m), rise time (0.4 s; height and time give gravity), fall gravity scale (1.35), short-jump scale (0.5), coyote time (0.12 s), jump buffer (0.14 s) |
| Air | air control (0.45) |
| Slopes and steps | max slope (48 degrees), step height (0.32 m), snap length (0.35 m) |
| Pushing | push strength (0.85), push mass (40 kg) |
| Actions | interact time and reach, hit stun, knockback, the landing speed that plays the landing clip, how long the landing lasts (0.3 s), the speed under which it counts as standing (0.15 m/s) |
| Body | capsule radius (0.34 m) and height (1.8 m) |
| Safety | the height below which it starts again at its spawn point (-25 m) |

Every number is read while the game runs, so you can change it in the remote inspector and see it at once; the capsule,
the steepest slope and the floor snap are applied again whenever the resource changes. The `Interactor`'s half angle (how
far from straight ahead still counts as in front, 75 degrees) is on that node.

The sample map is built for these numbers (blocks 1 m apart in height, twelve steps of 0.25 m, a 14 degree ramp): a test
fails when a tuning breaks it, which tells you which part of the map to rebuild.

The camera's settings are all on the `PlayerCamera` node, so you never open the Phantom Camera node: the nodes it
works with (Nodes), distance, the offset (x shoulder, y height, z depth), field of view, near and far clip and start
pitch (Framing), damping (Follow), mouse, stick and pitch limits (Orbit), the priority and the blend back from a
`CameraZone`'s camera (Blending), and the wall mask, shape and margin (Walls). They are applied to the `FollowCamera`
Phantom Camera when the game starts and again each time one changes, so they can be tuned in the remote inspector
while the game runs, and the node is a `@tool` script, so changing the distance or the field of view in the editor
moves the camera in the viewport. `Camera` renders and `PhantomCameraHost` copies the active Phantom Camera onto it,
so a change to `Camera` itself (its field of view, say) is overwritten: tune `PlayerCamera`. Anything else about it
(noise, tweens, dead zones) is that node's own inspector, and the addon's docs are at <https://phantom-camera.dev>.

The touch layer is a scene you arrange in the 2D editor (`ui/touch/touch_controls.tscn`): drag the `TouchStick` to
move where the stick waits, drag or resize the buttons under `SafeArea/Buttons` (instance `touch_button.tscn` for a new
one and set its action and word), resize the `MoveZone` and `LookZone` panels that decide which finger does what. Its
numbers are on `TouchControls` in `main.tscn`: when it shows, the stick's radius, dead zone and sprint ring, the look
sensitivity and smoothing, the opacity and the margin from the screen edge.

## Events other nodes connect to

`Player` emits `jumped`, `landed(impact_speed)`, `took_hit(amount, source)`, `interacted(target)`,
`item_collected(item_id, amount, total)`, `state_changed(state)` and `teleported`. A hit comes from calling
`player.hit(amount, source)`; the character stops for the stun time and is thrown away from the source.
`player.teleport(spot)` moves it and the camera cuts to it (the camera would otherwise fly there).

## Animation {#animation}

`PlayerAnimation` builds the player's `AnimationTree` in code, when the game starts and when the player scene is open in
the editor (it is a `@tool` script), so the AnimationTree panel shows the graph with no warning. Nothing generated is
saved into a scene file. The body is a state machine: `ground` (a blend space
on ground speed: idle, walk, run, sprint), `jump`, `fall`, `land` and `push`. On top is a one-shot layer for actions:
interact and hit play there, and so does anything else:

```gdscript
$Player/Animation.play_clip(CharacterClips.SWORD_ATTACK)
$Player/Animation.play_clip(CharacterClips.OPEN_CHEST, 1.0)  # taking 1 second
```

`CharacterClips` names every clip (`ual1/` and `ual2/` for the two libraries; the `_Loop` of a looping clip's name is
dropped on import and the clip loops) and lists all 86 in `CharacterClips.ALL`. The clip each state plays is an
inspector setting of `PlayerAnimation`. Both libraries use the Quaternius universal rig, which is the mannequin's, so
no retargeting is needed.

## Licences

The mannequin, both animation libraries and Phantom Camera are third-party files with a `LICENSE.md` each
(`assets/characters/mannequin/`, `assets/animation/universal/`, `addons/phantom_camera/`): CC0 for the Quaternius files
and MIT for Phantom Camera. Give them a line on the game's Credits screen.

## Testing it in a browser

`game/tools/web_smoke/touch_smoke.py` drives the web export in a phone-sized browser with real touch events: a drag
turns the camera by the designed angle, the stick moves the character, a tap jumps, and two fingers at once each do
only their own job. Run it under `gds quiet` (the command is in the file's header). It reads the state the game
writes to `window.gdprobe` when the page is opened with `?probe` (`ui/probe/web_probe.gd`).
