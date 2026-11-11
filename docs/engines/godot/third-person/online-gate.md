# The online client over a bad network

<!-- new section: the online client's page reached the size limit (kit #1198 merging main); the bad-network gate, its
     thresholds and how to run it, is a subject of its own -->

The repeatable pass/fail proof of [the online client](online-client.md) over a bad network, native and in the browser.
Part of [the 3D Third Person template](../third-person-template.md).

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
`tools/net/bad_network.py`. `--url wss://...` runs either against a deployment (no relay); `--walk spawn` walks round
the spawn across the dais's edge instead (gdstudio #1119);
`--break reconciler` (native only: the client's reconciler without the Deadnight #483 shift) or `--break hold` (the
server's `hold_ticks` 0) with `--expect-fail` is the teeth check, which CI runs after the gate.

| Check | Threshold | What it guards |
| --- | --- | --- |
| Lost | no answer past 6 m a stall (`Reconciler.resync`: the answer after k stalls with none between may be k walk-ons long) | a loop that does not settle |
| Snaps | one at the join, one per stall of the client's thread the stall guard saw, with stalls of the commands' way one per such stall for an answer under 4 m (`size_snaps_m`, #1110) | an error past 2.5 m outside a resync |
| Freezes seen | the stall guard counted at least the planned freezes | a run that froze nothing |
| Worst error | under 6 m a stall with freezes (`worst_stall_error_m`), under 4 m with stalls only (a stall of the commands' way outlasts the hold) | a stall shows as a burst, never a wrong place |
| Settled | under 5 cm two seconds after the body stands | the end state is the server's |
| Corrected | 4 m a minute (10 over a real network), 3 m more per stall of the commands' way, 0.75 m per unplanned stall of the client; a page 0.75 m per stall of its thread, the freezes included (1.5 m before #1127) | the server's hold |
| Starved puppets | 1 % of puppet-steps and 8 a puppet per stall of the client's thread (its catch-up frame), or per stall of the snapshots' way its length less the 100 ms delay, a snapshot more | the interpolation clock |
| Logs | nobody kicked, no `ERROR` in the server's or client's log; the page: no console error, no `Buffer payload full`, at least 20 frames a second | the transport |
| Page hitches | the page: at most one frame past 0.25 s in the 3 s after the seat (a stray one of the machine) | a join that meets the level's first draws |
| Page programs | the page: no GL program linked after the seat (`late_programs`, #1218) | a draw the warm-up missed |
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
| Native, relay and jitter, freezes, silence walk (six runs, #1127) | 248 to 282 ms | 8 to 120 (0.10 to 1.02 m; 3.98 m in a run whose server went over budget 50 steps) | 0 to 3 / 3 | 0.04 to 0.46 m | 0.1 to 7.8 mm | 3 to 150 of 5760 |
| Browser, relay, freezes, joined during the warm-up, silence walk (35 to 38 fps, three runs, #1127) | 252 to 280 ms | 28 to 70 (0.91 to 2.44 m) | 6 to 9 / 11 to 14 | 0.69 to 1.40 m | 1.4 to 8.1 mm | 45 to 168 of about 4000 |
| Browser, relay, freezes, joined after the warm-up, silence walk (28 to 35 fps, four runs, #1127) | 226 to 291 ms | 24 to 88 (0.47 to 1.85 m; 1.85 m in a run whose server lost 59 steps) | 0 to 2 / 3 | 0.15 to 0.46 m | 0 to 5.8 mm | 30 to 102 of about 4500 (459 in that run) |
| Native, Railway, freezes | 69 to 83 ms | 53 to 172 (0.68 to 3.07 m) | 3 / 3 | 2.67 to 2.81 m | 1.3 to 4 mm | 0 |
| Browser, Railway, freezes (33 fps) | 75 ms | 46 (1.25 m) | 8 / 11 | 4.21 m | 5.1 mm | 30 of 4062 |
| Teeth: native, server hold 0 | 234 ms | 726 to 736 (16.2 to 18.1 m) | | | | |
| Teeth: native, server hold 0, with jitter (Windows; the Linux runner without jitter read 2.4 m) | about 230 ms | 831 (32.3 m) | | | | |
| Teeth on the dais walk: hold 0 (Windows two cores; the runner) | | 58.1 m; 33.4 m | | | | |
| Teeth: native, reconciler unshifted (local and Railway) | 234 ms | 610 to 614 lost, 731 to 739 snaps, 20 to 241 km worst, 12 m off at the end | | | | |
| Teeth: browser, server hold 0 | 238 ms | 386 (31.3 m), one lost, 6.8 m worst | | | | |
| Teeth: browser, server hold 0, joined after the warm-up (two runs, #1106) | 254 to 262 ms | 44.8 to 45.6 m against 6.5 m allowed | | | | |

With the silence walk (#1127) the answer after a stall is centimetres off, so a stall of the page's thread costs about
what a stall of the native client's does: a page that joins after the warm-up (#1106) corrected at most 0.65 m a freeze
in the two seconds after it, so a page is allowed the hitch's 0.75 m a stall (`CORRECTED_M_A_PAGE_STALL`, 1.5 m before).

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
- **Approach:** Run the browser half with `--gpu` whenever the page draws AI puppets (`net_play_smoke.py --gpu --ai N`).
  **Watch out for:** SwiftShader drew 40 puppets at 7 frames a second, far under the floor above, while the GPU page
  passed every gate at 42. **Seen:** gdstudio #970, 2026-11-11.
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
- **Approach:** After a stall of the client's thread, step its body as the server stepped its own through the silence
  (`SilenceWalk`), and judge it by the speed gap of the first commands after the stall (each command's velocity on both
  sides), not by corrections. **Watch out for:** the snap put the point right but kept the body's speed from before
  the stall; the bodies then stepped the same commands at the same capped acceleration, so the gap lasted and every
  answer corrected the drift (a page's first freeze: a 0.70 m snap, then answers of 0.2 to 0.6 m, speeds 1.0 to 1.4
  m/s apart). Native sprints hit the speed cap sooner. Six page runs: 0.8 to 7 m/s apart, 1.1 to 4.2 m corrected in
  the 2 s after three freezes; walked 0.0 m/s in 13 of 14 freezes, 0.03 to 1.95 m; native 0.04 to 0.25 m a run, was
  0.7 to 0.9. **Seen:** gdstudio #1127, 2026-11-11 (the rest: late commands on a loaded machine).
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
  `by_second` and the relay's stalls near it (`WORST` lines). Count a snap by its cause: with up stalls, one under 4 m
  per up stall (`size_snaps_m`). **Watch out for:** the walk round the spawn crossed the dais's edge; a command
  repeated in an up stall took the server's body down while the client's stayed up, and each quarter of the correction
  landed inside the dais: 141 m corrected in one local run. On the dais top: 22.6 to 23.9 m. #1119
  fixed the client (`BodyOverlap`): the old walk (`--walk spawn`), three two-core stall runs, 25.0 to 32.4 m against
  28.8 to 62.2 m. A branch cut before the fix fails the stall run the same way: merge main, never rerun.
  **Seen:** gdstudio #1110, 2026-11-11 (from #1109); gdstudio #1146, 2026-11-11 (a camera fix, 2 snaps against 1); #1119.

- **Approach:** Number the commands from the smallest round trip of the last eight PONGs (`NetClient.RTT_WINDOW`),
  never the last; read the 5 s floor of `seq - server_tick` in the gate's `by_second` (a stale TICK spikes a second).
  **Watch out for:** a number may jump, never go back (the server drops a `seq` at or under its last), so one PONG
  held behind a stall of the network (450 to 590 ms, not 250) put the numbering 15 to 18 ticks ahead for good, and
  the map's moving parts stood up to 0.5 s apart on the two sides. #1108's check misses that PONG, and a freeze's
  too: it is read in the first poll after the freeze, before the stall guard's resync (main's client stood 43, 129,
  then 310 ticks ahead after the 0.5, 2 and 5 s freezes). **Seen:** gdstudio #1116, 2026-11-11 (stall runs ended 17
  to 27 ahead, main's 33 to 82; freeze runs 11 to 20 throughout; the held-PONG test).
- **Approach:** Judge a change's stall runs against main's client in the same made game, interleaved run by run
  (copy the one script in), and read the CPU load beside each. **Watch out for:** at 97 to 100 % CPU the starvation
  check failed on both sides (main's client 441 to 597 puppet-steps, the fix 498 to 867, bounds 530 to 620); its two
  worst runs each came with an unplanned stall of the client's thread, which the numbering does not touch.
  **Seen:** gdstudio #1116, 2026-11-11 (eight runs of main's client, nine of the fix; the browser half passed).
