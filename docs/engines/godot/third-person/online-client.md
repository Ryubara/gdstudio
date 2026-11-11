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
remembered points of the unanswered commands by every correction, snaps past 2.5 m, counts `lost` past 6 m (6 m a
stall for the answer after stalls of the client's thread: [the gate](#bad-network-gate)), and leaves an error under 1 cm
alone (a TICK carries centimetres: up to 0.87 cm of rounding). `fell` and `teleported` go through
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
lockstep route ends 0.000000 m off (`test_net_client_prediction.gd`); the closed loop in plain numbers ends at most 3.1
mm off at 50 to 400 ms with two pushes (`test_net_reconciler_loop.gd`); puppets drawn 100 ms behind over a link of 100
ms each way never starved in 240 steps; the TICK for eight players is 107 bytes (108 since #1073, less its moving props;
`test_net_client_link.gd`); 153 solid things are in both worlds at the same place (`test_world_parity.gd`).

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
and 24 s. The probe joins only after the level's warm-up (`EffectEmitter.warmed`) and 20 frames in a row under the
server's hold (`FrameSettle`), as a game joins behind its loading screen; the page records each frame's length and
the GL programs linked in it, and the report's `hitches` lists every frame past 0.25 s after the seat. Both judge with
`tools/net/bad_network.py`. `--url wss://...` runs either against a deployment (no relay);
`--break reconciler` (native only: the client's reconciler without the Deadnight #483 shift) or `--break hold` (the
server's `hold_ticks` 0) with `--expect-fail` is the teeth check, which CI runs after the gate.

| Check | Threshold | What it guards |
| --- | --- | --- |
| Lost | no answer past 6 m a stall (`Reconciler.resync`: the answer after k stalls with none between may be k walk-ons long) | a loop that does not settle |
| Snaps | one at the join, one per stall of the client's thread the stall guard saw, and with stalls of the commands' way one per such stall for an answer under 4 m (`size_snaps_m`, #1110) | an error past 2.5 m outside a resync |
| Freezes seen | the stall guard counted at least the planned freezes | a run that froze nothing |
| Worst error | under 6 m a stall with freezes (`worst_stall_error_m`), under 4 m with stalls only (a stall of the commands' way outlasts the hold) | a stall shows as a burst, never a wrong place |
| Settled | under 5 cm two seconds after the body stands | the end state is the server's |
| Corrected | 4 m a minute (10 over a real network), 3 m more per stall of the commands' way, 0.75 m per unplanned stall of the client; a page 1.5 m per stall of its thread, the freezes included | the server's hold |
| Starved puppets | 1 % of puppet-steps and 8 a puppet per stall of the client's thread (its catch-up frame), or per stall of the snapshots' way its length less the 100 ms delay, a snapshot more | the interpolation clock |
| Logs | nobody kicked, no `ERROR` in the server's or client's log; the page: no console error, no `Buffer payload full`, at least 20 frames a second | the transport |
| Page hitches | the page: at most one frame past 0.25 s in the 3 s after the seat (a stray one of the machine) | a join that meets the level's first draws |
| Server clock | the page's run: the server lost at most 15 steps between two `stats` lines | a run that measures the machine |

Windows, Godot 4.7.2, 2026-11-11 (Railway: the template's image, 48-core EPYC host; rows without jitter were run
before the relay jittered):

| Run | Round trip | Corrections (metres) | Snaps / stalls | Worst error | Settled | Starved puppet-steps |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| Native, relay, freezes (three runs) | 220 to 234 ms | 53 to 75 (0.69 to 0.93 m) | 3 / 3 | 2.72 to 2.93 m | 2.8 to 4.1 mm | 0 |
| Native, relay and 30 ms jitter, freezes | about 230 ms | 54 (0.75 m) | 3 / 3 | under 3 m | under 5 mm | 0 |
| Native, relay and jitter, 1 % stalls (17 to 19 up, 17 to 19 down) | about 240 to 270 ms | 207 to 271 (19.3 to 27.3 m) | 0 to 1 / 0 | 1.5 to 2.7 m | 2.2 to 5 mm | 669 to 714 of 5760 |
| Native, relay, 1 % stalls (22 to 26 up, 10 to 16 down) | 234 to 248 ms | 188 to 221 (11.2 to 16.4 m) | 0 / 0 | 1.42 to 1.52 m | 2.1 to 6.1 mm | 387 to 531 of 5760 |
| Native, relay and jitter, 1 % stalls, the walk on the dais (Linux runner, 13 runs, 26 up, 11 down) | | 20.7 to 21.1 m | 0 or 1 / 0 | 1.00 to 1.07 m | 2 to 8 mm | |
| Native, relay and jitter, 1 % stalls, the walk on the dais (Windows, two cores, six runs, 30 up, 12 down) | 245 to 277 ms | 22.6 to 23.9 m | 0 or 1 / 0 | 1.00 to 1.31 m | 0.2 to 7 mm | |
| Native, relay and jitter, freezes, the walk on the dais (Windows two cores, three runs; the runner 0.28 m) | | 0.25 to 0.37 m | 3 / 3 | 2.06 to 2.11 m | 4.6 to 4.7 mm | 0 |
| Browser, relay, freezes (34 to 40 fps, four runs) | 232 to 248 ms | 42 to 85 (0.67 to 5.17 m) | 4 to 8 / 10 to 12 | 4.18 to 6.00 m | 1.8 to 5 mm | 27 to 54 of about 4050 |
| Browser, relay, freezes, judged a stall (36 to 38 fps, three runs, #1070) | 234 to 264 ms | 41 to 57 (0.97 to 2.31 m) | 7 to 8 / 10 to 12 | 4.41 to 7.60 m, 2.20 to 2.53 m a stall (3 stacked) | 3.5 to 6.2 mm | 21 to 27 of about 4000 |
| Browser, relay, freezes, joined during the warm-up (main, 27 to 37 fps, eight runs, #1106) | 214 to 276 ms | 0.93 to 5.79 m (one run 28.3 m) | 4 to 9 / 11 to 14 | 4.51 to 7.50 m, 1.44 to 3.26 m a stall (4 stacked) | 0.6 to 8.7 mm | 18 to 81 of about 4000 (one 426) |
| Browser, relay, freezes, joined after the warm-up (28 to 31 fps, seven runs, #1106) | 238 to 304 ms | 1.66 to 4.59 m | 3 to 4 / 3 to 4 | 1.63 to 3.52 m (no stall stacked) | 1.1 to 8.7 mm | 24 to 78 of about 4500 (two runs whose server lost 40 and 55 steps: 366, 657) |
| Native, Railway, freezes | 69 to 83 ms | 53 to 172 (0.68 to 3.07 m) | 3 / 3 | 2.67 to 2.81 m | 1.3 to 4 mm | 0 |
| Browser, Railway, freezes (33 fps) | 75 ms | 46 (1.25 m) | 8 / 11 | 4.21 m | 5.1 mm | 30 of 4062 |
| Teeth: native, server hold 0 | 234 ms | 726 to 736 (16.2 to 18.1 m) | | | | |
| Teeth: native, server hold 0, with jitter (Windows; the Linux runner without jitter read 2.4 m) | about 230 ms | 831 (32.3 m) | | | | |
| Teeth on the dais walk: hold 0 (Windows two cores; the runner) | | 58.1 m; 33.4 m | | | | |
| Teeth: native, reconciler unshifted (local and Railway) | 234 ms | 610 to 614 lost, 731 to 739 snaps, 20 to 241 km worst, 12 m off at the end | | | | |
| Teeth: browser, server hold 0 | 238 ms | 386 (31.3 m), one lost, 6.8 m worst | | | | |
| Teeth: browser, server hold 0, joined after the warm-up (two runs, #1106) | 254 to 262 ms | 44.8 to 45.6 m against 6.5 m allowed | | | | |

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
  seated under `gds quiet`. Even at 34 to 40 frames a second the page hitched past 0.25 s about eight times in 30 s
  (the warm-up it joined during: below), so snaps are allowed per stall the stall guard saw. The CI runner (ubuntu,
  four cores) drew the same page at 14 frames a second, so the browser half is not a CI step. **Seen:** gdstudio #908, 2026-11-11
  (`net_play_smoke.py` `MIN_FPS`; the first CI run of #1077 failed on it).
- **Approach:** Before comparing a browser client with a native one, trace each answer taken whole after a resync
  (its error, the stalls since the last answer taken), and judge it per stall (`Reconciler.resync`,
  `worst_stall_error`). **Watch out for:** every page answer past 3 m came in its first three seconds, after two to
  four hitches of 0.3 to 0.9 s with no answer between: the server walks its body on 30 steps after each silence and
  the walk-ons add up (four at 4 m/s, 7.1 m). Per stall the page reads 2.2 to 2.5 m, the native client 2.6 to 3.0 m.
  A PONG read after a freeze measured the freeze (5.2 s) and put the numbering 5 s ahead; it is now ignored
  (`NetClient.resync`). **Seen:** gdstudio #1070, 2026-11-11 (the hitches: next entry).
- **Approach:** Join a page only once the level has drawn everything: after the level's warm-up
  (`EffectEmitter.warmed`) and then 20 frames in a row under the server's hold (`FrameSettle`), as a game joins
  behind its loading screen; count the page's frames past 0.25 s after the seat and the GL programs linked in them.
  **Watch out for:** the probe joined at once, about 0.3 s after the level started, and the warm-up went on for 6 s
  after the seat: its tour of the reflection probes drew on SwiftShader at 0.3 to 1.4 s a frame, which the stall
  guard saw as stalls (8 to 10 of them, 4 to 6 in the first 3 s, 2.5 to 2.8 s of the page's time). After the change:
  no program linked after the seat, 0 hitches in six of seven runs, 3 stalls (the freezes), worst error 1.6 to 3.5 m
  instead of 4.5 to 7.5 m. The page joins 1.4 to 2.3 s later (`settle_ms`). **Seen:** gdstudio #1106, 2026-11-11.
- **Approach:** When a run's allowance grows with something you take away, measure what it covered before you
  tighten it: a page's corrections are judged per stall of its thread (1.5 m), freezes included. **Watch out for:**
  the hitches' allowance (0.75 m each) had hidden that a page at 24 to 35 frames a second corrects 1 to 5 m in the
  second after each freeze (the native client 0.7 to 0.9 m for all three); without the hitches the page failed the
  old 2 m in eight of eleven runs. Four of 19 runs failed their starvation bound because the game server itself lost
  0.3 to 1.7 s of steps to the shared machine, so the page's run now checks the server's clock first. **Seen:**
  gdstudio #1106, 2026-11-11 (`CORRECTED_M_A_PAGE_STALL`, `SERVER_LOST_STEPS`; why a page's freeze costs more:
  #1127).
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

## Playing online {#play-online}

<!-- new section: the client was only reachable from tests and probes; nothing said how a player or a developer enters
     the online game, what the screen says when it fails, how a bot plays it, or what it costs in a browser -->

`online_main.tscn` (a root scene beside `main.tscn`) is the online game: an instance of the offline game, unchanged,
with a `NetClient`, the `RemotePlayers` and an `OnlineStatus` overlay (`ui/online/`). It is entered three ways:

| From | How | Notes |
| --- | --- | --- |
| The main menu | Play online | joins `MainMenu.server_address`, or the address field under the button, which shows in a debug build only (`address_field`): a player never meets an address; `NetClient.next_url` carries it into the scene |
| The command line | `-- --connect ws://host:8910 [--name Ada] [--bot route\|watch] [--onlineprobe]` | `MenuScene` goes straight to `online_scene`, once a run: back to the menu shows the menu |
| A page | `index.html?url=wss://host[&name=Ada][&bot=watch][&onlineprobe]` | an `https` page may open `wss://` only; a page with `?netplay` stays the bad-network probe's |

The overlay shows Connecting until the WELCOME, then hides; on `REFUSED` it names the reason (another version, with a
Reload button on the web and "update the game" on the desktop; the game is full; another map), on a link that closes
before the WELCOME or `connect_seconds` of frames (each under the stall guard's 0.25 s) without one it says the server
did not answer, and on a seated link that closes, Connection lost. Every message has Back to menu, the player's input
is off while one shows, and the texts are exports of `online_status.tscn`.
The overlay is not under the router's stage, so it builds its `gds_ui` theme from the tokens itself (the marquee
panel's padding, the title's size; [Menus](../menus.md#menus)); `tests/ui/test_online_status.gd` holds every part
inside the panel's bulbs at the desktop and the phone layout, and `tools/capture/online_status_tour.tscn` shows
Connecting, a message and the other-version message in the real online game (Movie Maker at 1920 x 1080, or
`-- --shots=<folder>` in an 844 x 390 window).

`PlayerBot` (`gameplay/player/player_bot.gd`, `--bot` or `?bot`) plays through the player's own `PlayerInput`: it
presses the input actions (`Input.action_press`) and turns the camera with `PlayerCamera.orbit`, so the server hears a
person's commands. `route` walks to the main door, opens it, comes back, fires three shots past the other player and
stands; `watch` keeps the nearest puppet in the middle of the view and fires at its chest after `fire_after` seconds.
A capture is a server and two clients, one bot each (the watcher records):

```text
godot --headless --path game -- --server --port 8931
gds godot -- --path game --write-movie <scratch>/client2.avi --fixed-fps 30 --quit-after 1100 -- --connect ws://127.0.0.1:8931 --bot watch --name Two
gds godot -- --path game -- --connect ws://127.0.0.1:8931 --bot route --name One      # 8 s later
```

`tools/web_smoke/online.py` (under `gds quiet`) is the browser's proof: the server of `gate_server.gd`, a relay of
100 ms each way, two pages of the web export with `?url=<relay>&bot=route|watch&onlineprobe`; every page seated, every
player seen, a round trip read, nothing lost, the body within 1.5 m of the server's point, no console error and no
`Buffer payload full`, nobody kicked. `--other-version` points it at `tools/net/other_version_server.gd`, which answers
every hello as a server of the next protocol version: the probe then fails (its teeth), and with `--expect-refused` it
passes only when every page shows the overlay's "another version" message. `OnlineProbe` (`ui/probe/`) is the page's
side: `window.gdonline`, or an `ONLINE_PROBE` line a second on the desktop with `--onlineprobe`.

**What it measured** (Windows, Godot 4.7.2, 2026-11-11, Ryzen 7 9800X3D and RTX 5080; headless Chromium 156 at
320x180 under `gds quiet`, one page, `server_bot.gd` bots for the puppets (`--bots` 1, 4 and 7), relay 100 ms each way,
20 s). On the GPU (`--gpu`, ANGLE on Direct3D 11) a warm-up page played 20 s first (below); vsync holds a GPU page at
16.7 ms whatever it draws, so `--uncapped` (vsync and the frame cap off) reads the page's work, two runs each:

| Puppets | Renderer | Frames a second | Frame p50 / p95 | Placing the puppets, p50 | Corrections (metres) |
| ---: | --- | ---: | ---: | ---: | ---: |
| 1 | SwiftShader | 23 | 42.8 / 48.7 ms | 0.1 ms | 40 (1.6 m) |
| 4 | SwiftShader | 21 | 46.1 / 50.6 ms | 0.2 ms | 18 (1.8 m) |
| 7 (8 players) | SwiftShader | 19 | 51.8 / 63.7 ms | 0.3 ms | 14 (1.1 m) |
| 1 | GPU, vsync | 60 | 16.6 / 18.3 ms | 0.1 ms | 11 (0.3 m) |
| 4 | GPU, vsync | 60 | 16.7 / 17.8 ms | 0.2 ms | 12 (0.5 m) |
| 7 (8 players) | GPU, vsync | 60 | 16.6 / 18.0 ms | 0.3 ms | 41 (2.5 m) |
| 1 | GPU, uncapped | 166 to 230 | 4.1 to 6.6 / 5.5 to 10.0 ms | 0.1 ms | 41 to 53 (1.6 to 2.5 m) |
| 4 | GPU, uncapped | 135 to 140 | 7.6 to 7.8 / 10.3 to 11.0 ms | 0.2 ms | 29 to 60 (0.7 to 2.7 m) |
| 7 | GPU, uncapped | 79 to 94 | 10.5 to 14.3 / 13.6 to 18.3 ms | 0.4 ms | 17 to 19 (0.7 m) |

Each puppet costs the software-drawn page about 1.5 ms a frame and the GPU page 1 to 1.3 ms (with no puppet the
uncapped page made a frame in 1.7 to 2.2 ms): nearly the same, so the cost is the page's own work for each puppet (its
animation and skinned model), not the drawing, and placing it from the track is a few hundredths of it. Eight players
hold 60 frames a second with vsync on a desktop GPU, but their frame is 10.5 to 14.3 ms of work (p95 up to 18.3 ms),
against the research's estimate of about 1 ms for all eight; on SwiftShader they draw at 19. Two pages at once share
the CPU and draw at 15 there.

**A cold browser hangs up on its first join.** Godot's Compatibility renderer links each shader program the first time
it draws with it and asks for the link's result at once (`getProgramParameter`), which waits until Chrome's GPU process
has compiled it. On ANGLE's Direct3D 11 the first page waited 21.2 s in 342 calls to `getProgramParameter` (171
programs, the slowest about 1.1 s each), in long tasks of 13.9, 4.8 and 3.0 s from the first frames; the socket opened
before the first of them, its `open` event ran 14 s later, and the server had hung up on a connection with no hello at
`NetServer.hello_seconds` (10 s; close code 1008): the overlay said the server did not answer. SwiftShader links the
same programs in 0.3 s (its longest task 2.4 s), which is why software pages always seated. The browser keeps what it
compiled: a second page in the same browser, or the same profile started again, drew at 60 frames a second and seated
in a second. So `online.py --gpu` plays a warm-up page for `--warm-up` seconds (20) first, and the measured pages read
a returning player; the warm-up page itself is hung up every time. The private desktop was not the cause: the warm
page ran on it. A player whose browser has never drawn the game meets the same hang-up (#1137). Two GPU pages after
the warm-up seat and hold 60 frames a second; two SwiftShader pages failed four runs of four later the same day, on a
machine busy with other agents (main's probe too, and with a warm-up): the second page hitched 2.7 to 8 s while the
first drew, and was hung up for its hello in the same way.

**Jolt in wasm against Jolt on Linux.** `StepTraceProbe` (`ui/probe/`, `?steptrace` or `-- --steptrace` with
`--play`) steps a server's body (`character.tscn`) 1800 times through the template's map with commands of the step's
number alone (a turn, sprints, a jump every 97 steps: 124 m, onto and off the raised floor) and prints its position
every 30 steps; `tools/web_smoke/step_trace.py` compares the web build's trace with the desktop's and with any given
trace file. The web build (wasm), Windows and Linux (the pinned Linux Godot, in WSL) gave **the same positions to nine
decimals at every point**: the client's prediction in a browser and the server's step on Linux do not part ways by
themselves. The route bot's corrections over a real socket (one client, no relay, 32 s, two runs each):

| Client | Server | Round trip | Corrections (metres) | Worst error | Stall-guard resyncs |
| --- | --- | ---: | ---: | ---: | ---: |
| Native, Windows | local, Windows | 16 to 17 ms | 4 to 5 (0.03 m) | 0.02 m | 0 |
| Native, Windows | Railway, Linux | 79 to 83 ms | 4 to 5 (0.03 m) | 0.02 m | 0 |
| Browser, SwiftShader | local, Windows | 53 to 58 ms | 32 to 50 (3.0 to 4.7 m) | 2.4 to 3.7 m | 4 to 7 |
| Browser, SwiftShader | Railway, Linux | 81 to 86 ms | 28 to 44 (2.0 to 4.0 m) | 2.2 to 2.3 m | 5 to 6 |

The browser's corrections are its own hitches (each over 0.25 s is a resync and a snap: 4 to 6 snaps a run, 99 to
126 catch-up ticks skipped), the same with either server; the native client reads the same 0.03 m against Windows and
Linux. The page's hitches after the join are #1106.

- **Approach:** Aim a bot (or any program that shoots for a player) from the crosshair ray's origin,
  `camera.project_ray_origin(centre)`, not from the body or the camera's position. **Watch out for:** the
  over-the-shoulder lens is shifted half a metre to the side, so a watcher whose camera yaw pointed at the other
  player's chest from its own eye fired 24 shots and killed nobody: every ray passed beside the body. Aimed from the
  ray's origin, the first three shots killed. **Seen:** gdstudio #909, 2026-11-11 (`PlayerBot.face`; the test measures
  the ray's miss distance, under 0.3 m).
- **Approach:** Answer "does the browser predict what the server steps" with a trace of the body's step on each
  platform, commands from the step's number and no network, before reading corrections over a socket. **Watch out
  for:** the browser corrected 30 to 100 times more than a native client against the same Linux server, which looked
  like Jolt in wasm parting from Jolt on Linux; the three traces were the same to nine decimals and the corrections
  were the page's hitches. **Seen:** gdstudio #909, 2026-11-11 (`StepTraceProbe`, `step_trace.py`).
- **Approach:** Count the puppets a probe's page sees from its own report (`puppets`), and give a docstring's argument
  arithmetic a run before trusting it. **Watch out for:** the probe's docstring said `--bots` 0, 3 and 6 give 1, 4 and
  7 puppets; one page sees one puppet a bot, and the first GPU sweep of #1117 measured 0, 3 and 6 before the report's
  `puppets` field showed it. **Seen:** gdstudio #1117, 2026-11-11 (fixed in `online.py`'s docstring; the table's rows
  are `--bots` 1, 4 and 7).
- **Approach:** Count a connect timeout in frames the game really ran (each under the stall guard's 0.25 s), and show
  Back to menu while connecting. **Watch out for:** a page's first seconds are spent compiling shaders and loading the
  map; a timeout on the clock would call a server that is fine unreachable on a slow device. **Seen:** gdstudio #909,
  2026-11-11 (`OnlineStatus.connect_seconds`).

## The long proofs: unread client, hostile cost, soak, bandwidth {#soak-and-bandwidth}

<!-- new section: the gate above is 30 s runs; nothing held the proofs that need a minute or ten (a client that stops
     reading, the hostile clients' cost, the soak, bytes per player) or the choices made where #908 asked the
     impossible -->

The rest of gdstudio #908 (gdstudio #1071), and what was chosen where #908 asked for what no client can pass: the
1 % of stalled chunks of [the gate](#bad-network-gate) stays (2 % starve 40 % of the steps at a 100 ms delay, measured
there), and the 60 s unread client is a client whose downlink stalls while it still sends (below). Windows, Godot
4.7.2, 2026-11-11, other agents using the machine.

- **The unread client** (`tests/gameplay/test_net_server_unread.gd`, the template job): eight players, one of them
  behind `tests/fixtures/tcp_relay.gd`, which stops reading the server's side for 60 s of the frame clock while the
  client still sends; a ninth join's churn (a `left` and a `joined` every 5 s) owes it 24 events. After the stall it has
  every event once, in order, TICKs in order and of all eight, and the server never hung up on it. On loopback the
  sockets held the whole minute (228 KB through the relay, no send refused), so a second case makes the listener refuse
  every send to that peer (as a full `outbound_buffer` does): 1811 sends refused, `peers_stalled` in seven `stats`
  lines, and still every event. Taking out "the events wait" (`sent_events` called on a refused TICK) loses 22 of
  the 24 events. In the browser, `tools/web_smoke/net_play_smoke.py --unread 60 --bots 7` (a workstation run) holds the
  page's downlink 60 s while the page plays: 270 KB down, 2383 TICKs read of the 2340 sent (none lost), 3646 steps of
  starved puppets (the stall itself), settled 1.8 mm, no `Buffer payload full`, nobody kicked.
- **The hostile cost** (`tests/gameplay/test_net_server_hostile_cost.gd`): the honest player beside a stream of hostile
  clients (a flood, junk sizes and types, a packet over 4 KB, a lying `seq`, a second hello, a socket that never reads),
  each hung up on and the next connecting at once, against windows with two polite players in the same seats (a seated
  hostile's body costs a player's step: against the honest player alone the median read twice the baseline). Three
  rounds of 300 frames: median step 0.28 to 0.35 ms hostile against 0.35 to 0.39 ms quiet, 95th percentile under 4 ms,
  54 hostile clients, 36 of them kicked. With the command rate limit taken out the flood is never hung up on: median
  2.9 ms against 0.32 ms.
- **The soak** (`tools/net/soak.gd`; `.github/workflows/net-soak.yml`, nightly, by hand, and on a pull request that
  changes it): the server and two predicting clients of `OnlineRig` over real sockets, ten game minutes at
  `--fixed-fps 60` in 69 s of wall time; each client walks 1040 to 1217 m; every 300 ticks, once both stood a second,
  each body is 0.0 mm from the server's and every solid thing is in both worlds (`tests/fixtures/world_parity.gd`, the
  same comparison as `test_world_parity.gd`); no correction, snap or loss; memory 204 KB more after the first minute,
  no node more; server step 0.29 ms mean, 0.42 ms at the 95th percentile; no `ERROR` in the verbose log. `--break solid`
  (a wall in one client's world only) and `--break leak` (a node kept at every check) each fail.
- **Bandwidth** (`tools/net/bandwidth.py`, in the same workflow): every client through the relay, which counts each
  connection; 10 s once all are seated (`--ai 40,120` adds an AI crowd on the server: [the AI's
  numbers](ai.md#replication-cost)). The research's budgets (down 5 KB/s, up 2 KB/s a client):

| Players | Down a client | Up a client |
| ---: | ---: | ---: |
| 2 | 1140 B/s | 1286 B/s |
| 4 | 1857 B/s | 1286 B/s |
| 8 | 3298 B/s | 1286 B/s |

  Up is the same at any count: 60 commands a second of 15 bytes and the WebSocket frame's 6 (a client's frames are
  masked), and two pings.

- **Approach:** Test a client that stops reading by stalling its downlink and nothing else (a relay that stops reading
  the server's side), and keep "the client stopped sending" for the silence rule. **Watch out for:** #908 asked for a
  60 s unread client while the server hangs up on 15 s without a command: a frozen client stops both, so the server
  rightly drops it at 15 s (`test_net_server_silence.gd`); the one that can be unread for a minute still sends, and
  Godot's `WebSocketLink` sends only when polled, so the stall has to be made under the socket, not by not polling.
  **Seen:** gdstudio #1071, 2026-11-11 (`TcpRelay.hold_down`, `Relay.hold_down`).
- **Approach:** Prove a full send buffer with a listener that refuses sends to one peer, and report what the real
  sockets held. **Watch out for:** on Windows loopback the sockets under a 16 KB `outbound_buffer` took the whole minute
  of eight players (some 230 KB) without one refused send, so a test that waits for the kernel to fill passes without
  ever reaching the refusal path. **Seen:** gdstudio #1071, 2026-11-11 (`FullListener` in the unread suite).
- **Approach:** Compare a server's step under hostile clients with a baseline that has as many polite players in the
  seats the hostile ones take. **Watch out for:** a hostile client that is seated gets a body the server steps like any
  player's, so against the honest player alone the hostile median read 0.26 ms to 0.12 ms, twice, and none of it was
  the attack. **Seen:** gdstudio #1071, 2026-11-11 (`test_net_server_hostile_cost.gd`, the `Polite` clients).
- **Approach:** Measure a soak's walk as the path its bodies took, summed every tick. **Watch out for:** the distance
  between two checks of a body walking circles is a chord, under 5 m on most checks, and the first soak failed its
  own "the autopilot ran" check twenty times. **Seen:** gdstudio #1071, 2026-11-11 (`soak.gd` `_track_walks`).
