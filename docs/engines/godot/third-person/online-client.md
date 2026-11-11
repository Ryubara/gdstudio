# The online client

<!-- new section: the game-server page holds what the server admits, steps and sends; nothing held how the template's
     client predicts its own body, draws the others, or what that costs -->

The 3D Third Person client of [the game server](game-server.md#template-server): it predicts the local player and
draws the others as puppets. Part of [the 3D Third Person template](../third-person-template.md); the packets are
[the template's packets](../multiplayer.md#template-packets).

## What it does {#template-client}

<!-- new section: gdstudio #905 added the client; nothing said how a TICK reaches the local body and the puppets -->

`NetClient` (`gameplay/net/net_client.gd`) runs before the bodies (`process_physics_priority` -20) and turns its
player's own `_physics_process` off. Each physics step:

1. The link is polled. A WELCOME seats the client and puts the body at the slot's spawn, computed in the client's own
   map by the server's function (`NetServer.spawn_transform_in`), so the two bodies start at the same float, not at the
   WELCOME's centimetres. A TICK gives the `Reconciler` the server's point for the last command applied (`ack`), and
   gives every other entry, `joined` and `left` to `RemotePlayers`.
2. `StallGuard` judges the step: more than 0.25 s since the last on the machine's clock is a resync (the reconciler
   forgets its points and takes the next answer whole), and for 0.5 s after it every tick that is not the first of its
   process frame is skipped (the engine's catch-up ticks: no command, no step).
3. The body moves by the correction under way (`Reconciler.take`).
4. The controller is sampled, the command numbered and encoded; the body steps once with the decoded packet
   (`Character.step`, the server's own step), and the point it reached is recorded for that number.
5. A ping goes out twice a second.

Before the prediction the step plays the server's shots, hits and deaths that are due (`ClientCombat`, [shots
online](online-shots.md#template-shots)): the local player's at once, the others' when the puppets are drawn at their
TICK.

The `Reconciler` never replays (a step has side effects: [the character's snapshot](character.md#controller)): it
measures the error of the answered command, moves the body a quarter of what is left each frame, shifts the
remembered points of the unanswered commands by every correction, snaps past 2.5 m, counts `lost` past 6 m, and leaves
an error under 1 cm alone (a TICK carries centimetres: up to 0.87 cm of rounding). `fell` and `teleported` go through
`Player.teleport()` and reset it.

`RemotePlayers` (`gameplay/net/remote_players.gd`) makes one puppet `Player` a slot from `player.tscn`
(`Player.make_puppet()`, then `PlayerPuppet`), draws each `delay` (0.1 s) behind its clock, between the two snapshots
around that moment (`InterpolationTrack`: one second kept, a jump over 6 m is a warp, a moment past the newest holds it
and counts as `starved`). The clock is the newest TICK's server time moved on by each step, pulled a tenth of the way
to each TICK as it comes and set to it when 0.3 s off.

`NetServer.hold_ticks` (4) is the server's half of the bargain: a body whose client's queue is empty waits that many
steps without stepping before it repeats the last command (`PeerSlot.HELD` in the history; `steps_held` and
`steps_repeated` in the `stats` line).

- **Approach:** Prove prediction exact in lockstep first (a `LoopbackListener`, each side in a `SubViewport` with a
  world of its own, a route with turns, jumps and a ramp: the same float), then count corrections across real
  processes. **Watch out for:** in one process the route ended 0.000000 m off, but a client in another process
  corrected 399 times (12 m in 20 s) on localhost and 821 times (19.8 m in 36 s) through a 100 ms relay: as the two
  processes' frames drifted a command landed a step late about thirteen times a player a second, the server repeated
  the last one and its body ran a step ahead. A hold of four steps before a repeat (`hold_ticks`) took it to 5 (0.04 m)
  and 54 (0.69 m, three freezes included). **Seen:** gdstudio #905, 2026-11-11
  (`test_commands_that_arrive_unevenly_are_waited_for_not_repeated`, `tools/net/predict_bot.gd`).
- **Approach:** Judge a stall guard's skip by the process frame of each tick, and only in a short window after the
  stall. **Watch out for:** a freeze made inside a tick is seen by the next tick of the same frame, but the engine's
  catch-up ticks come in the next frame, so a guard that skipped the rest of the stalled frame skipped nothing (0
  skipped over three freezes); skipping every second tick of a frame at all times would halve the commands of a game
  drawn at 30 frames a second. **Seen:** gdstudio #905, 2026-11-11 (7 ticks skipped a freeze after the fix).

## Puppets {#puppets}

<!-- new section: multiplayer.md#appearance says remote bodies are the same scene; nothing said what a puppet needs
     from the character so its animation, footsteps and camera stay unchanged -->

A puppet is the local scene with three things taken away: its `PlayerInput` is freed (no input, and no reader of the
camera), its collision layer is 0 (nothing meets it; its mask keeps the world for the floor test), and its
`_physics_process` returns at once, so `step` never runs (no move, no weapon tick, no pickup, no health regeneration).
It joins no group (`player` is what the HUD, the minimap and a camera zone look for) and goes to no spawn point.
`PlayerPuppet.place` writes exactly what the drawing parts read from a stepped body: `state`, `velocity` (from the two
snapshots around the moment), `facing` and the model's turn, `view_pitch`, `crouching`, `aiming` and an eased
`aim_amount`, the sprint flag, the crouch and prone amounts (with `crouch_changed`, `aim_changed`, `prone_changed`),
and refits the capsule. `CharacterAnimation` needed nothing new.

- **Approach:** Give a body placed by hand the engine's floor contact with a short move through its point (3 cm above
  it, moved down; up while the entry says it is in the air), then put it back on the point. **Watch out for:**
  `is_on_floor()` is set only by `move_and_slide`, so a puppet placed by `global_position` never had a floor and
  `Footsteps` (which asks it) played no step. The slide is not sent, so a puppet's footsteps play through a slide.
  **Seen:** gdstudio #905, 2026-11-11 (`PlayerPuppet._touch_floor`).
- **Approach:** In one process with several clients (tests, a side-by-side capture), give each client's
  `PhantomCameraHost` and its `PhantomCamera3D`s a `host_layers` bit of their own. **Watch out for:** the addon's
  hosts choose among every Phantom Camera in the process, whatever viewport it is in, so both clients' screens showed
  the last client's follow camera while each viewport's `get_camera_3d()` was still its own `Camera3D`: a test that
  reads only the viewport's camera passes. The game itself runs one client a process. **Seen:** gdstudio #905,
  2026-11-11 (`OnlineRig._own_cameras`; the test asks the host's `get_active_pcam()`).

## What it measured {#client-costs}

<!-- new section: the numbers of the client against a real server, which #908's bad-network proof builds on -->

Windows, Godot 4.7.2, a headless server process, bots of `tools/net/server_bot.gd` in another and
`tools/net/predict_bot.gd` (circles, sprints every other lap, a jump every 3 s) in a third, through
`tools/net/relay.py` where a delay is given; freezes of the client's own thread at 8, 16 and 24 s for 0.5, 2 and 5 s.
Times are microseconds of a physics step: `NetClient` includes the body's own step.

| Run | Round trip | Corrections (metres) | Worst error | Snaps / lost | End gap | `NetClient` p50 / p95 | 3 or 7 puppets placed, p50 / p95 |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| Localhost, 7 bots, no hold (before) | 34 ms | 399 (12.1 m in 20 s) | 0.33 m | 0 / 0 | 6 mm | 212 / 332 | 100 / 135 |
| Localhost, 7 bots, `hold_ticks` 4 | 34 ms | 5 (0.04 m) | 0.02 m | 0 / 0 | 5 mm | 200 / 315 | 99 / 135 |
| Relay 100 ms each way, 3 bots, freezes, no hold (before) | 227 ms | 821 (19.8 m in 36 s) | 3.45 m | 3 / 0 | 0.9 mm | 256 / 407 | 57 / 97 |
| Relay 100 ms each way, 3 bots, freezes, `hold_ticks` 4 | 221 ms | 54 (0.69 m) | 2.83 m | 3 / 0 | 1.4 mm | 224 / 347 | 55 / 87 |
| Relay 200 ms each way, 3 bots, freezes, `hold_ticks` 4 | 435 ms | 65 (0.81 m) | 2.82 m | 3 / 0 | 1.7 mm | 215 / 332 | 52 / 92 |

The worst error is the 5 s freeze (the server repeated the last command for 30 steps, then stood); each freeze is one
snap and seven skipped ticks; no puppet starved in any run, and the server logged no `kicked` line. In the suites: the
lockstep route ends 0.000000 m off (`test_net_client_prediction.gd`); the closed loop in plain numbers ends at most
3.1 mm off at 50 to 400 ms with two pushes (`test_net_reconciler_loop.gd`); puppets drawn 100 ms behind over a link of
100 ms each way never starved in 240 steps; the TICK for eight players is 107 bytes (`test_net_client_link.gd`); 153
solid things are in both worlds at the same place (`test_world_parity.gd`).
