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
4. The controller is sampled, the command numbered (by the server tick it is expected to be stepped at:
   `first_seq` at the WELCOME, moved on when a TICK shows the numbers trail it, `renumbered`; the map's doors and
   platforms are put at that tick first, [networked map parts](net-world.md#net-world)) and encoded; the body steps
   once with the decoded packet (`Character.step`, the server's own step), and the point it reached is recorded for
   that number.
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

## The bad-network gate {#bad-network-gate}

<!-- new section: the costs above are one-off measurements; nothing held the repeatable pass/fail proof of the client
     over a bad network, native and in the browser, or what its thresholds guard -->

A gate with thresholds, its native half run in the kit's `template` CI job, both halves by hand against any server
(gdstudio #908). The native half is `tools/net/bad_network_gate.py`: the server of `--server` started by
`tools/net/gate_server.gd` (free port; `--hold-ticks` for the teeth check), three `server_bot.gd` bots for puppets,
`tools/net/relay.py` with 100 ms each way (each chunk up to 30 ms more, in order: a real network's jitter), and
`predict_bot.gd` through it, running 2 m circles on the spawn dais's flat top, never across its 1 m edge
(`--centre 0,0 --radius 2 --lap 3.5 --no-sprint`, #1110), in two runs of 30 s: `freeze` (the client's own thread
frozen 0.5, 2 and 5 s) and `stalls` (1 % of the relayed chunks held 300 ms more, everything behind them waiting too:
TCP's loss). The browser half is `tools/web_smoke/net_play_smoke.py`: the web export opened with
`?play&netplay&url=ws://<relay>` gets a
`NetPlayProbe` (`ui/probe/`, made by the player rig only on such a page) that plays online with a `NetClient`, walks a
`CirclingController` and writes `NetPlayReport` to `window.gdnet`; the page's thread is frozen by a busy loop at 8, 16
and 24 s. Both judge with `tools/net/bad_network.py`. `--url wss://...` runs either against a deployment (no relay);
`--break reconciler` (native only: the client's reconciler without the Deadnight #483 shift) or `--break hold` (the
server's `hold_ticks` 0) with `--expect-fail` is the teeth check, which CI runs after the gate.

| Check | Threshold | What it guards |
| --- | --- | --- |
| Lost | no answer past 6 m (the page: one) | a loop that does not settle |
| Snaps | one at the join, one per stall of the client's thread the stall guard saw, and with stalls of the commands' way one per such stall for an answer under 4 m (`size_snaps_m`, #1110) | an error past 2.5 m outside a resync |
| Freezes seen | the stall guard counted at least the planned freezes | a run that froze nothing |
| Worst error | under 6 m with freezes (the page: 8 m, #1070), under 4 m with stalls only (a stall of the commands' way outlasts the hold) | a stall shows as a burst, never a wrong place |
| Settled | under 5 cm two seconds after the body stands | the end state is the server's |
| Corrected | 4 m a minute (10 over a real network), 3 m more per stall of the commands' way, 0.75 m per unplanned stall of the client | the server's hold |
| Starved puppets | 1 % of puppet-steps and 8 a puppet per stall of the client's thread (its catch-up frame), or per stall of the snapshots' way its length less the 100 ms delay, a snapshot more | the interpolation clock |
| Logs | nobody kicked, no `ERROR` in the server's or client's log; the page: no console error, no `Buffer payload full`, at least 20 frames a second | the transport |

Windows, Godot 4.7.2, 2026-11-11 (Railway: the template's image, 48-core EPYC host; rows without jitter were run
before the relay jittered):

| Run | Round trip | Corrections (metres) | Snaps / stalls | Worst error | Settled | Starved puppet-steps |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| Native, relay, freezes (three runs) | 220 to 234 ms | 53 to 75 (0.69 to 0.93 m) | 3 / 3 | 2.72 to 2.93 m | 2.8 to 4.1 mm | 0 |
| Native, relay and 30 ms jitter, freezes | about 230 ms | 54 (0.75 m) | 3 / 3 | under 3 m | under 5 mm | 0 |
| Native, relay and jitter, 1 % stalls (17 to 19 up, 17 to 19 down) | about 240 to 270 ms | 207 to 271 (19.3 to 27.3 m) | 0 to 1 / 0 | 1.5 to 2.7 m | 2.2 to 5 mm | 669 to 714 of 5760 |
| Native, relay, 1 % stalls (22 to 26 up, 10 to 16 down) | 234 to 248 ms | 188 to 221 (11.2 to 16.4 m) | 0 / 0 | 1.42 to 1.52 m | 2.1 to 6.1 mm | 387 to 531 of 5760 |
| Browser, relay, freezes (34 to 40 fps, four runs) | 232 to 248 ms | 42 to 85 (0.67 to 5.17 m) | 4 to 8 / 10 to 12 | 4.18 to 6.00 m | 1.8 to 5 mm | 27 to 54 of about 4050 |
| Native, Railway, freezes | 69 to 83 ms | 53 to 172 (0.68 to 3.07 m) | 3 / 3 | 2.67 to 2.81 m | 1.3 to 4 mm | 0 |
| Browser, Railway, freezes (33 fps) | 75 ms | 46 (1.25 m) | 8 / 11 | 4.21 m | 5.1 mm | 30 of 4062 |
| Teeth: native, server hold 0 | 234 ms | 726 to 736 (16.2 to 18.1 m) | | | | |
| Teeth: native, server hold 0, with jitter (Windows; the Linux runner without jitter read 2.4 m) | about 230 ms | 831 (32.3 m) | | | | |
| Teeth: native, reconciler unshifted (local and Railway) | 234 ms | 610 to 614 lost, 731 to 739 snaps, 20 to 241 km worst, 12 m off at the end | | | | |
| Teeth: browser, server hold 0 | 238 ms | 386 (31.3 m), one lost, 6.8 m worst | | | | |

The client costs 190 to 290 µs a step at the median (`NetClient`, the body's step included). The relay carried 41 KB up
and 73 KB down in the freeze run's 35 s connection (about 1.2 and 2.1 KB/s) for a client with three other players.

- **Approach:** Judge starvation by puppet-steps (`RemotePlayers.starved` adds one for each puppet that starved on a
  step), and bound it by what the network forces: a stall of the snapshots' way starves the puppets for its length
  less the interpolation delay, a snapshot's interval more (a 300 ms stall, 14 steps). **Watch out for:** the first
  report divided by steps alone and read three times the starvation, which looked like a clock that recovers slowly
  after a burst; a trace of each TICK's arrival against the clock showed 14-step streaks, one a stall, and a burst
  that put the clock right at once. 2 % of chunks stalled (the issue's number) starve 40 % of the steps at a 100 ms
  delay: no client can pass that, so the gate stalls 1 % and judges against the forced bound. **Seen:** gdstudio #908,
  2026-11-11 (`NetPlayReport`, `Network.starved_allowed`).
- **Approach:** Run a browser probe of the game loop in a small page (320x180) and fail a run whose page drew under 20
  frames a second: it measures the machine, not the client. **Watch out for:** SwiftShader drew the 1280x720 page at
  6 frames a second, the client stepped 30 times a second instead of 60, the server repeated its commands, and the
  gate read 13.8 m of corrections and two lost answers that were the renderer's; a page with `--enable-gpu` never
  seated under `gds quiet`. Even at 34 to 40 frames a second the page hitches past 0.25 s about eight times in 30 s,
  so snaps and corrections are allowed per stall the stall guard saw. The CI runner (ubuntu, four cores) drew the
  same page at 14 frames a second, so the browser half is not a CI step. **Seen:** gdstudio #908, 2026-11-11
  (`net_play_smoke.py` `MIN_FPS`; the first CI run of #1077 failed on it).
- **Approach:** Give a teeth check a condition the broken part cannot pass on any machine: the relay jitters each
  chunk up to 30 ms (in order), which the server's hold of four steps absorbs and a server without it turns into
  repeated commands. **Watch out for:** without jitter, the hold-0 run read 16 to 18 m of corrections on Windows but
  2.4 m on the Linux runner (against 0.7 m with the hold, a threshold of 2 m): the two processes' frames drifted too
  little there for a command to land late, and the teeth check passed by 0.4 m. With the jitter: 0.75 m with the
  hold, 32.3 m without. **Seen:** gdstudio #908, 2026-11-11 (`bad_network_gate.py` `JITTER_MS`).
- **Approach:** Deploy the game server from a game made from the template (`gds template game`, its `server/`), never
  from the kit's `templates/3d-third-person/`. **Watch out for:** the kit's template folder has no synced addons
  (`gds_ui`, `gds_game`, Phantom Camera), so the image built, the deployment read `SUCCESS`, and the server failed to
  parse its scripts; the edge answered the client's upgrade with a 502. **Seen:** gdstudio #908, 2026-11-11 (the
  deployment from the made game listened on `$PORT` at once).
- **Approach:** Keep a gate's walk off every ledge the body can fall from or climb, and read a failed run by second:
  `by_second` (where the body stood, metres corrected, snaps, gap) and the relay's stalls near it (`WORST` lines). Count
  a snap by its cause: with up stalls, one under 4 m per up stall (`size_snaps_m`). **Watch out for:** the walk round
  the spawn crossed the dais's edge; a command repeated in an up stall took the server's body down while the client's
  stayed up, and each quarter of the correction landed inside the dais and was pushed back on top (#1119): 141 m
  corrected in one local run, 75.5 m and 1.65 m apart standing on 31cc1793. On the dais top, six two-core runs: 22.6
  to 23.9 m, worst 1.0 to 1.31 m. **Seen:** gdstudio #1110, 2026-11-11 (from #1109).
