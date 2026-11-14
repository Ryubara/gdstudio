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
   forgets its points and takes the next answer whole, and the body first steps as the server stepped its own through
   the silence: `SilenceWalk`, below), and for 0.5 s after it every tick that is not the first of its process frame is
   skipped (the engine's catch-up ticks: no command, no step).
3. The body moves by the correction under way (`Reconciler.take`).
4. The controller is sampled, the command numbered (by the server tick it is expected to be stepped at:
   `first_seq` at the WELCOME, moved on when a TICK shows the numbers trail the TICK's tick and the smallest of the
   last eight round trips, `numbering_rtt_ms`, `renumbered`; the map's doors and
   platforms are put at that tick first, [networked map parts](net-world.md#net-world)) and encoded; the body steps
   once with the decoded packet (`Character.step`, the server's own step), and the point it reached is recorded for
   that number.
5. A ping goes out twice a second (`rtt_ms` is the last PONG's round trip, `rtt_samples` the last eight).

Before the prediction the step plays the server's shots, hits and deaths that are due (`ClientCombat`, [shots
online](online-shots.md#template-shots)): the local player's at once, the others' when the puppets are drawn at their
TICK.

The `Reconciler` never replays (a step has side effects: [the character's snapshot](character.md#controller)): it
measures the error of the answered command, moves the body a quarter of what is left each frame, shifts the
remembered points of the unanswered commands by every correction, snaps past 2.5 m, counts `lost` past 6 m (6 m a
stall for the answer after stalls of the client's thread: [the gate](#bad-network-gate)), and leaves an error under 1 cm
alone (a TICK carries centimetres: up to 0.87 cm of rounding). A part that puts the body more than 5 cm inside the
world (`BodyOverlap`, the body's shapes laid against the world with its mask) is followed by the rest of the correction
at once (`Reconciler.take_rest`, counted in `stuck_snaps`): a body on a ledge whose server body stands below it would
be pushed back out after each part. `fell` and `teleported` go through `Player.teleport()` and reset it.

`SilenceWalk` (`gameplay/net/silence_walk.gd`) is the client's half of the server's silence rule: a server whose
client sends nothing holds the body `NetServer.HOLD_TICKS` (4) steps, steps the last command again without its presses
for `COMMAND_TICKS` (30), then stands it (`PeerSlot.take`). On a resync the client steps its own body the same way at
once, for every tick of the stall but the one that ends it (`NetClient.silent_steps`), the standing steps until the
body is at rest on the floor (two seconds at most), so the two bodies come out of a stall with the same point and the
same speed. The snap alone puts the point right and keeps the speed the body had before the stall ([the
gate](#bad-network-gate) has the trace).

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
- **Approach:** Take a correction whole once a part of it puts the body inside the world: lay the body's shapes
  against the world after the part (`collide_shape`, the deepest contact pair) and hand out the rest past 5 cm.
  **Watch out for:** a body on the dais's top whose server body stood against the wall below never met it while the
  controller walked it back on top (the gate's walk round the spawn): each quarter landed inside the dais, the step put
  it back, and the shifted points hid that for a round trip (240 ms: 1.4 m apart after 3 s, 12.5 m corrected). Under
  Jolt the motion test's `recovery_as_collision` depth is what is left after one recovery pass (0.033 m for 0.25 m
  inside): read the contact pairs. **Seen:** gdstudio #1119, 2026-11-11 (`test_net_ledge_correction.gd`; about 5 µs a
  frame that takes a part).

## Puppets {#puppets}

<!-- new section: multiplayer.md#appearance says remote bodies are the same scene; nothing said what a puppet needs
     from the character so its animation, footsteps and camera stay unchanged -->

A puppet is the local scene with three things taken away: its `PlayerInput` is freed (no input, and no reader of the
camera), its collision layer is 0 (nothing meets it; its mask keeps the world for the floor test), and its
`_physics_process` returns at once, so `step` never runs (no move, no weapon tick, no pickup, no health regeneration).
It joins no group (`player` is what the HUD, the minimap and a camera zone look for) and goes to no spawn point.
`PlayerPuppet.place` writes exactly what the drawing parts read from a stepped body: `state`, `velocity` (from the two
snapshots around the moment), `facing` and the model's turn, `view_pitch`, `view_yaw` (along the facing, turned by
the aim's heading off the body while aiming), `crouching`, `aiming` and an eased `aim_amount`, the sprint flag, the
crouch and prone amounts (with `crouch_changed`, `aim_changed`, `prone_changed`), and refits the capsule.
`CharacterAnimation` needed nothing new.

**The aim off the body** (kit #1277). Sliding, the body keeps along the slide and the
[aim layer](shooting.md#aim-layer) turns the upper body to the aim; the layer reads the aim from `view_yaw` and
`view_pitch`. An aiming player's entry ends with one signed byte, `Character.aim_yaw` (the view's heading off the
facing, a half turn either way, about 1.4 degrees a step), sent only while the aim flag is on; `PlayerPuppet.place` sets
`view_yaw` to `facing - PI + aim_yaw`, and `InterpolationTrack` blends it as an angle. On a slide aimed 50 degrees to
each side (`test_net_puppet_aim.gd`, loopback), Bo's puppet of Ada pointed its pistol 49.8 and -48.8 degrees off its
body (her own screen 49.8 and -48.8), the muzzle within 0.5 degrees of its aim and the body along the slide; without
the byte it pointed 0.5 degrees off its body. The cost: one byte a TICK for each aiming player (the TICK of two players
is 37 bytes, 38 while one aims; eight players 109, 117 all aiming; the longest WELCOME 2303), so 30 B/s down a client
for each aiming player at 30 TICKs a second, nothing for one who does not aim. The capture is
`tools/capture/puppet_aim_tour.tscn` (Ada's screen beside Bo's).

**Its starts and stops** (gdstudio #1420). `GaitTransitions` picks a start, a stop or a reversal from the body's goal
(`Character.goal_speed` and `move_goal.direction(body)`), which a stepped body reads from its last command. A puppet has
none: `PlayerPuppet.make` sets the body's `CharacterGoal.from_motion`, and `RemotePlayers` sets its `motion` each step with
`PlayerPuppet.goal_of`: nothing once the entry's `halt` flag says the player asked for no move (bit 7 of the flags
byte, set by the server from the body's goal, protocol 13, no byte more), else the velocity between the two newest
snapshots (`InterpolationTrack.heading`, 0.1 s ahead of the moment drawn), and the goal it had while that heading is
under 0.5 m/s (a reversal passes through 0; a stepped body's goal never does). The track takes `halt` from the snapshot
the drawn move heads to, so a stop begins with the move toward the halted snapshot. On the gait tour (Ada's screen beside
Bo's) the puppet now plays `Walk_Stop`, `Jog_Stop` and `Sprint_Stop` where her own body does, about 6 frames after it
(the draw delay), and its largest bone turns 10 to 20 degrees a frame while it moves, against 0.1 to 0.2 before; tested
by `test_net_puppet_gait.gd`. The goal's speed comes from the entry (gdstudio #1453): the server puts the command's
goal speed in the state byte's top four bits, in fifteenths of the body's sprint speed (`PlayerEntry.goal_step`,
`SnapshotCodec.goal_step`; the 15 states fit the low four; protocol 17, no byte more), and `goal_of` scales the heading's
way to it (along the goal it had, or the facing, while the heading is too slow to tell a way). On the gait tour the
puppet now plays `Idle_To_Jog` and `Idle_To_Sprint` where her own body does, 6 frames after it; tested by
`test_net_starts.gd`, which also proves her own predicted body plays all three starts from standing (it did once
`START_GRACE` landed, gdstudio #1427).

Its animation throttle and render layer: [what a puppet costs](puppet-cost.md#puppet-cost). How a puppet shows a
vault it never stepped: [a puppet's vault](traversal.md#online).

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
- **Approach:** For every part of the drawing code a puppet runs, list what it reads from the body and check each
  value is written by `PlayerPuppet.place` or worked out from the snapshots; a value from `last_command`, or a getter
  built on it (`goal_speed`), is empty on a puppet. **Watch out for:** the gait transitions read `goal_speed`, always 0
  on a puppet, so every moving puppet was taken for a body asked to stop and slid along in the walk's stop clip's last
  frame; the drawn motion alone could not tell a stop from a slow-down to a jog in the first 0.1 s of the brake (a
  brake guess either picked the jog's stop for a sprint or a stop for a slow-down), so one free flag bit carries the
  stop. **Seen:** gdstudio #1420, 2026-11-13 (`PlayerPuppet.goal_of`, `PlayerEntry.halt`); #1453, 2026-11-14 (the
  heading's speed made jog and sprint starts the walk's; the goal speed rides in the state byte).
- **Approach:** Film a puppet's turn off its body (an aim to the side) from ahead of it, on a lane read from the level's
  scene (each block's place and size) before the first run, with the watcher's camera turned to follow it; put a test's
  route on the same lane. **Watch out for:** from beside or above at 5 to 10 m a 50 degree aim and an aim along the
  body looked the same (the before and after captures could not be told apart while the suite measured 49.8 against
  0.5 degrees); routes picked blind started inside the ragdoll ledge and ran into crates and the steps, and the
  slide's 8 m/s carried the body 10 m past a watcher in a second. **Seen:** gdstudio #1277, 2026-11-11
  (`puppet_aim_tour.tscn`, five captures before the front view); #1367, 2026-11-13 (`puppet_gait_tour.tscn`: a
  column beside the watcher filled his camera's view).

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

The gate with thresholds that proves the client over a bad network, native and in the browser, and how to run it:
[the online client over a bad network](online-gate.md#bad-network-gate).

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

The client joins once the level is ready, as a game joins behind its loading screen (`NetClient.join_after_warm_up`,
on): `JoinWait` (`gameplay/net/join_wait.gd`) waits for the level's warm-up (`EffectEmitter.warmed`) and then for
`FrameSettle` (20 frames in a row each under the stall guard's 0.25 s, at most 10 s), the bad-network probe's wait
with a looser frame (the probe's is the server's hold, 67 ms).
The overlay shows Loading meanwhile (the link is not open yet, so none of it counts towards `connect_seconds`), then
Connecting until the WELCOME, then hides; on `REFUSED` it names the reason (another version, with a
Reload button on the web and "update the game" on the desktop; the game is full; another map), on a link that closes
before the WELCOME (after the new sockets of a late hello, below) or `connect_seconds` of frames (each under the stall
guard's 0.25 s) without one it says the server did not answer, and on a seated link that closes, Connection lost.
Every message has Back to menu, the player's input is off while one shows, and the texts are exports of
`online_status.tscn`.
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

`tools/web_smoke/online.py` (under `gds quiet`) is the browser's proof: the server of `gate_server.gd`, a relay of 100
ms each way, two pages of the web export with `?url=<relay>&bot=route|watch&onlineprobe`; every page seated, every
player seen, a round trip read, nothing lost, the body within 1.5 m of the server's point, no console error and no
`Buffer payload full`, nobody kicked. `--other-version` points it at `tools/net/other_version_server.gd`, which answers
every hello as a server of the next protocol version: the probe then fails (its teeth), and with `--expect-refused` it
passes only when every page shows the overlay's "another version" message. The pages open together (a page opened after
another was seated would load its level inside the first one's join window), each records every frame (`FRAME_WATCH` of
`net_play_smoke.py`), and a page fails with more than one frame past 0.25 s in the 3 s after its seat, the gate's bound;
the report lists every such frame, `settle_ms` and `wait_ms` (the join's wait). `OnlineProbe` (`ui/probe/`) is the
page's side: `window.gdonline`, or an `ONLINE_PROBE` line a second on the desktop with `--onlineprobe`.

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

Each puppet cost the software-drawn page about 1.5 ms a frame and the GPU page 1 to 1.3 ms (with no puppet the
uncapped page made a frame in 1.7 to 2.2 ms; the first puppet also turns the route bot's view, so read the cost from 1
to 7). Two pages at once share the CPU and draw at 15 there.

**Where a puppet's frame went (#1138):** mostly the minimap drawing every body again; seven puppets now take 3.8 to
4.2 ms on the GPU page (10.5 to 14.3 before), [what a puppet costs](puppet-cost.md#puppet-cost).

**A cold browser hangs up on its first join.** Godot's Compatibility renderer links each shader program the first time
it draws with it and asks for the link's result at once (`getProgramParameter`), which waits until Chrome's GPU process
has compiled it. On ANGLE's Direct3D 11 the first page waited 21.2 s in 342 calls to `getProgramParameter` (171
programs, the slowest about 1.1 s each), in long tasks of 13.9, 4.8 and 3.0 s from the first frames; the socket opened
before the first of them, its `open` event ran 14 s later, and the server had hung up on a connection with no hello at
`NetServer.hello_seconds` (10 s; close code 1008): the overlay said the server did not answer. SwiftShader links the
same programs in 0.3 s (its longest task 2.4 s), which is why software pages always seated. The browser keeps what it
compiled: a second page in the same browser, or the same profile started again, drew at 60 frames a second and seated
in a second. So `online.py --gpu` plays a warm-up page for `--warm-up` seconds (20) first, and the measured pages read
a returning player. The private desktop was not the cause: the warm page ran on it. Two GPU pages after the warm-up
seat and hold 60 frames a second; two SwiftShader pages failed four runs of four later the same day, on a machine busy
with other agents (main's probe too, and with a warm-up): the second page hitched 2.7 to 8 s while the first drew, and
was hung up for its hello in the same way.

**A late hello gets a new socket** (#1137). When the server hangs up before the WELCOME with
`NetServer.CLOSE_POLICY` (1008, the hello window passed), `NetClient` opens a new socket to the same address, up to
`rejoins` (2) times, and says nothing to the overlay meanwhile; a REFUSED, a server that is not there (no close code)
or a seated link that closes is never retried. The page's own hang-up then costs one handshake, since the programs
are compiled by the time the first close is read. `online.py` reports each page's `join_s` (the page's load to its
seat, as the player waits) and the page's `rejoined` (Windows, Godot 4.7.2, RTX 5080, 2026-11-11, one page, one bot,
relay 100 ms each way):

| Browser | Before: seated, join | After: seated, join, new sockets |
| --- | --- | --- |
| GPU, cold profile (`--gpu --warm-up 0`) | 0 of 2 (closed at 19 s, the overlay unreachable) | 3 of 3, 21.9 to 22.2 s, 1 each |
| GPU, after a 20 s warm-up page | seated in #1117 (not timed) | 1 of 1, 3.0 s (the warm-up page itself seated at 21.6 s) |
| SwiftShader, cold | 2 of 2, 4.8 to 6.8 s | 2 of 2, 5.1 to 6.3 s, none |
| SwiftShader, two pages (`--pages 2`) | 0 of 4 on a busy machine (above) | 2 of 2, the second page 16.1 to 18.4 s, none |

A cold GPU page still waits about 21 s for its programs before anything plays: the compile itself, which a
loading screen, a warm-up before the join (#1142) or Chrome's parallel compile would have to hide; the rejoin only
keeps that wait from ending in "The server did not answer". Since then the web program list links every program
before the engine draws ([Linking every program at once](../first-use-hitches.md#prelink), started by the page itself
since #1214: [the page starts it](../first-use-hitches.md#prelink-page)), and the same cold join seats 6.5 to 7.3 s
after the page opened; the rows above are the history of the hang-up, not today's join.

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

**The join after the warm-up** (#1142; Windows, Godot 4.7.2, 2026-11-11, the same SwiftShader page, `online.py`
with the route bot, relay 100 ms each way; a hitch is a frame past 0.25 s after the seat, the join window its first
3 s):

| Join | Runs | Hitches in the join window | Worst hitch | Programs linked after the seat | Join's wait (settle) |
| --- | ---: | ---: | ---: | ---: | ---: |
| At once (`join_after_warm_up` off, as before) | 3 | 2 to 3 (fails) | 1.10 to 1.66 s | 53 to 54 | |
| After the warm-up, settled under the server's hold | 3 | 1 each (283 to 419 ms, nothing linked) | 0.42 s | 1 to 5 | 9.3 to 10.2 s (1.35 to 1.41 s) |
| After the warm-up, settled under the stall (shipped) | 4 | 0 | 0.38 s, 8.7 s after the seat | 0 to 4 | 9.2 to 10.0 s (1.05 to 1.45 s) |
| Two pages at once (13 to 14 fps), settled under the server's hold | 1 | 0 | 0.43 s | 0 to 7 | 25 to 28 s (10 s: the limit) |
| Two pages at once, settled under the stall (shipped) | 2 | 0 | 0.25 s | 0 to 1 | 18 to 19 s (1.2 to 1.6 s) |

The page shows Loading for the warm-up's 8 to 9 s on SwiftShader (about 80 frames: in a Movie Maker capture at 10
frames a second it is 8 s of Loading, two frames of Connecting, then play).

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
- **Approach:** Join a player's game only after the level's warm-up and settled frames (`JoinWait`), say Loading
  meanwhile, and count a frame settled under the stall guard's stall, not the server's hold. **Watch out for:** the
  online game joined on ready, so a page met the warm-up's 1.1 to 1.7 s frames as stalls in its first 3 s (2 to 3
  hitches, 53 programs linked after the seat); and with the probe's hold of 67 ms, a page drawn at 13 frames a
  second (two pages on one CPU, or a Movie Maker capture) never had 20 short frames in a row and waited out the
  whole 10 s limit on Loading; a suite that waited 240 frames for a join ran out once the warm-up grew. **Seen:**
  gdstudio #1142, 2026-11-11 (`online.py` judges the join window); gdstudio #1297, 2026-11-11 (the minimap's tour:
  `test_online_main.gd` waits 600).
- **Approach:** Count the puppets a probe's page sees from its own report (`puppets`), and give a docstring's argument
  arithmetic a run before trusting it. **Watch out for:** the probe's docstring said `--bots` 0, 3 and 6 give 1, 4 and
  7 puppets; one page sees one puppet a bot, and the first GPU sweep of #1117 measured 0, 3 and 6 before the report's
  `puppets` field showed it. **Seen:** gdstudio #1117, 2026-11-11 (fixed in `online.py`'s docstring; the table's rows
  are `--bots` 1, 4 and 7).
- **Approach:** Let a client whose hello the server refused for lateness (close 1008 before the WELCOME) open a new
  socket by itself, a bounded number of times, and keep the overlay at Connecting. **Watch out for:** a browser holds
  the socket's `open` event behind the page's long tasks while the server's clock runs: a cold GPU page compiled its
  shaders for 14 s, the hello left after the server's 10 s window, and the overlay told a first-time player the server
  did not answer, though a second try seated in a second. Never retry a REFUSED or a seated link that closes.
  **Seen:** gdstudio #1137, 2026-11-11 (`NetClient.rejoins`; `test_online_main.gd` hangs up on every hello at once).
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
  numbers](ai-online.md#replication-cost)). The research's budgets (down 5 KB/s, up 2 KB/s a client):

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
