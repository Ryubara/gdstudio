# Browser probes: writing them, running them, gating on them

<!-- new section: web-export.md grew past what one page holds; this is the half about the probes themselves -->

How to drive the web build of a game in a headless browser and read it back, from Deadnight's web smoke
(`tools/web_smoke/smoke.py` there, Playwright driving the export). What the browser build does differently is on
[Web export](web-export.md); the game write-up is Deadnight's `docs/research/web-export.md`.

**Run every local browser probe through `gds quiet`** (Windows): under pointer lock headless Chrome confines the real
cursor of the person at the machine to its hidden window at the top left of the screen, until Esc ([no focus](no-focus.md#browser-probes-and-any-other-program-gds-quiet)):

```text
uv run --project <kit>/python gds quiet -- uv run --with playwright==1.64.1 python tools/web_smoke/<probe>.py <args>
```

A hook refuses a `tools/web_smoke/*.py` or Playwright run without it. CI runners have nobody at the machine; the
command is the same there (off Windows it starts the program normally).

## Running a probe {#running}

| Topic | What we learned |
| --- | --- |
| Pointer lock in headless Chromium | It works (`document.pointerLockElement` is the canvas after the click that starts the night), but on Linux, the CI runner, every synthetic `page.mouse.move` under lock arrives as a motion and then the opposite motion (+15 px, -15 px), which cancel. Windows does not do it. A smoke that must turn the view dispatches `new PointerEvent('pointermove', {movementX, bubbles: true})` on the canvas: Godot's web runtime listens for `pointermove` and reads `movementX/Y`. Check mouse look on the CI runner, not only on your own machine. |
| Key taps | Godot reads input once per frame, so a tap shorter than a frame can be lost: hold keys for about 150 ms. |
| Focus after Back | After Back from a screen nothing has focus; the router spends the first arrow or accept key giving it focus. |

- **Approach:** Protect the person at the machine from every local program that can take the mouse or the keyboard, by
  what it does and not by name: run any browser probe through `gds quiet`, which frees the cursor every 5 ms on a
  private desktop. **Watch out for:** the quiet-run rule named Godot only, while headless Google Chrome under pointer
  lock calls `ClipCursor` on its hidden window (measured `(17, 68, 864, 541)` for the whole lock) and trapped the
  cursor in an invisible box until Esc; Playwright's default headless shell did not clip. **Seen:** gdstudio,
  2026-11-02 (fix: `gds quiet` wraps any command and a hook refuses a `tools/web_smoke` run without it; 0 of 777
  samples held, the lock still took).
- **Approach:** Treat Playwright's headless browser as software-rendered: record its numbers as "runs without a GPU",
  never gate on them, and launch `channel="chrome"` for real-GPU numbers and for a smoke with several pages at once.
  **Watch out for:** `headless=True` starts `chromium-headless-shell` on SwiftShader (12 to 15 fps on a PC with an RTX
  card), a new Playwright version needs its own browser build (`playwright install chromium-headless-shell`), and
  three or four pages at once stalled the third and fourth on software GL. **Seen:** Deadnight, 2026-11-01 (fix: a
  `--gpu` mode on `channel="chrome"` for the multi-page smokes).
- **Approach:** In CI, install the probe's browser so that an unreachable Ubuntu mirror cannot fail the job: try
  `playwright install --with-deps` once, then fall back to the browser alone (the runner image has Chromium's libraries;
  `--with-deps` only adds fonts). Each call runs under `timeout -k 30 <seconds>` and the step has a `timeout-minutes`
  far under the job's (12 of 40; a normal install takes about 20 s). **Watch out for:** a DNS outage of
  `azure.archive.ubuntu.com` failed the `template` job for over an hour (apt retries about eight minutes); a fallback
  only covers a call that returns, and apt's switch to `archive.ubuntu.com` went silent and held the step 39 minutes.
  **Seen:** gdstudio #1224, 2026-11-11 (fix: #1226, the fallback in both `ci` files); gdstudio #1201's run
  43062712944, 2026-11-11 (fix: #1235, the limits, pinned by `test_workflow_browser_install.py`).
- **Approach:** When the browser tools find no connected browser, start Chrome with `--headless=new
  --remote-debugging-port=9333` and a throwaway profile and speak the DevTools protocol over Node's built-in
  `WebSocket`: `Page.captureScreenshot`, `Page.startScreencast` for a transition (about 30 frames a second),
  `Input.dispatchKeyEvent`, `Runtime.evaluate` for frame times. **Watch out for:** the extension needs a signed-in
  Chrome of the same account, so a headless session answers "Browser extension is not connected"; a gamepad cannot be
  injected this way. **Seen:** Deadnight, 2026-11-01 (fix: direct protocol, no package downloaded; the GPU still
  works through ANGLE).
- **Approach:** Before blaming the desktop for a GPU page that stalls in its first seconds, time its WebGL calls from
  an init script (wrap each `WebGL2RenderingContext.prototype` method, keep the calls over 50 ms) and measure a warm
  browser, one that played the game once. **Watch out for:** a cold Chrome on ANGLE's Direct3D 11 blocked the page
  21 s in `getProgramParameter` (Godot reads each link at once; 171 programs) where SwiftShader took 0.3 s, and a probe
  whose socket opened meanwhile was hung up for a missing hello, which read as the private desktop starving the page.
  Fresh Playwright browsers are always cold: a GPU probe plays a warm-up page first (`online.py --warm-up`). The
  headless shell with `--enable-gpu` does draw on the GPU. **Seen:** gdstudio #1117, 2026-11-11 (a player's cold
  first join: #1137).

## The boot check every template runs {#boot-check}

<!-- new section: CI exported the web build and never opened it; a script failing only in a browser passed (#921) -->

The kit's `template` job and a game's own `web` job open the web export in headless Chromium after exporting it
(`game/tools/web_smoke/boot_check.py`, a file the kit syncs into every game from `templates/game/`). It serves
`build/web`, opens `index.html?probe` and waits for the game's probe to write `ready` to `window.gdprobe` (`WebProbe`
in 3D Blank, `MenuProbe` in the menu of 3D Third Person). It fails on a console error, a page error, a request that
failed or answered 400 or more (the favicon aside), or no `ready` within 60 s, printing the engine's own
`#status-notice` when there is one. It records, and never gates on, the seconds to the first frames, the longest frame
in the 3 s after them, and the sizes of the pack, the wasm and the folder, as a table in the job summary and in
`<out>/boot.json`; a shot of the first frames goes to `<out>/boot.png`. A template that has
`tools/web_smoke/touch_smoke.py` runs it in the next step (3D Third Person: 17 checks, 21 s on a PC and about 90 s on the
runner, at `--ratio 1 --no-shots`), and both write their files to a `web-smoke` artifact.

Run the same step locally from a made game (`gds template game <template>` keeps one for probes), after
`godot --headless --path game --export-release Web` with the pinned Godot:

```text
uv run --project <kit>/python gds quiet -- uv run --with playwright==1.64.1 python game/tools/web_smoke/boot_check.py build/web build/boot
```

A game that has no probe in its main scene fails with "did not report ready": add a node that writes `ready` (the 3D
Blank `ui/probe/web_probe.gd` is 34 lines) rather than loosening the check.

- **Approach:** Time the first frames of a page with `performance.now()` read inside the `requestAnimationFrame` callback,
  never the callback's timestamp argument. **Watch out for:** the argument is when the frame began, and the engine's
  start blocks the main thread for most of a second, so the callback ran late and its timestamp read 0.17 s while the
  page took 1.03 s to say ready. **Seen:** gdstudio #921, 2026-11-10 (fix: `WATCH` in `boot_check.py`).
- **Approach:** Keep a boot check's `ready` for what the game's probe says and the frame time as a note: a first-use
  hitch (a shader linked at the first shot, [first-use hitches](first-use-hitches.md)) is outside it, because the boot
  never fires. **Watch out for:** the longest frame in the seconds after ready was 0.6 to 0.8 s in both templates on
  software GL, which is the first frames' own shader work and not a regression; read it against `main`'s runs of the
  same runner. **Seen:** gdstudio #921, 2026-11-10 (the first-shot hitch of #946 is not seen by it).

- **Approach:** A smoke that measures a distance or a turn in a duration waits on the game's own clock: the probe writes
  `ticks` (`Engine.get_physics_frames()`) and the smoke waits for N ticks (`sim_wait` in `touch_smoke.py`), and CI opens
  a phone page at a device pixel ratio of 1 (`--ratio 1`) without its pictures (`--no-shots`; a failure still leaves
  `failed.png`), since every check reads the canvas's own scale. **Watch out
  for:** on the runner's software renderer the same `time.sleep(0.8)` was a fraction of the game time, so "keeps
  walking after the look finger lifts" read 0.28 m and then 0.56 m against 2 m on a PC, and the whole smoke took 4 min
  16 s at ratio 2 (the page drew 1688 by 780 pixels in SwiftShader). **Seen:** gdstudio #921, 2026-11-10 (fix: ticks
  and `--ratio 1`).

- **Approach:** A check that a press caused an effect waits on the game's word that it began (the probe's `jumps`),
  then watches the effect from that sample (the rise, until it passes 0.3 m or 90 ticks), never a window of ticks
  counted from the press. **Watch out for:** the old jump check read the height for 30 ticks from a snapshot taken
  before the press, the jump takes about 30 ticks to its apex and the first sample after a press is 14 to 17 ticks in,
  so a press reaching the game late left too little window, and over 30 ticks none ("jumps 0 to 1, rose 0.00 m"). A
  page 30 times slower and a main thread held for 6 s did not reproduce it; `--throttle` and `--stall-jump` of
  `touch_smoke.py` try it. **Seen:** gdstudio #991, 2026-11-10 (fix: waits on `jumps`; 20 of 20 runs passed).

## What a probe can see {#what-a-probe-sees}

- **Approach:** Give a browser test a probe node that, only when `OS.has_feature("web")` and the page asks for it
  (`?probe`), writes the top screen's name and a few counters to a window object (`JavaScriptBridge.create_object`, a
  few times a second); the test polls it with `page.evaluate`. **Watch out for:** every screen is one `<canvas>`, with
  no element, text or role to wait on, so a Playwright run of a web export is blind without it; a hook that runs in
  every player's page costs them bridge calls ([the bridge's
  calls](web-heap.md#test-hooks-cost-the-players-page-count-the-bridges-calls)). **Seen:** Deadnight,
  2026-11-01; Deadnight #907, 2026-11-04 (fix: the probe, then added only on `?probe`).

| Topic | What we learned |
| --- | --- |
| A saved file in a browser run | A web export keeps `user://` in the page's IndexedDB: database `/userfs`, object store `FILE_DATA`, one record a file under `/userfs/godot/app_userdata/<project name>/<file>`, its bytes in `contents` (`new TextDecoder().decode(record.contents)`). A run proves that a file survives a reload by reading it there with `page.evaluate` (list the store's keys when the path is wrong: the project name is part of it), reloading the same context (a new context has empty storage) and reading what the game found again through `window.deadnight`; the write is mirrored from the page a moment after the file is closed, so poll for it. Two traps met on the way: Deadnight's `smoke.probe` returns only the keys the older probes read, so a new probe key is read with `Object.assign({}, window.deadnight)` (as `lobby.py` does), and a lobby the first visit made is still held by the backend after the reload (409 `already_in_lobby`: leave it first). Deadnight `tools/web_smoke/guest_account.py` (#1080). |
| A probe that needs the rules to say yes | A grenade, a purchase or a revive is refused until the first round is on, and a solo night is in its intro for a while after `running` is true ("ROUND 00"): the client goes on drawing a preview of what the server refused. Wait for `round >= 1` and read the server's own word through the probe (`grenade_cooking`: `GrenadeServer.is_cooking`), never the picture. Deadnight `tools/web_smoke/touch_weapon_places.py` (#1280). |
| A last request when the page closes | A `fetch` or beacon sent from `pagehide` is proved by closing a real tab (`page.close()`) in Chromium, Firefox and WebKit, against a deployed backend or a proxy that holds each request 150 ms. `sendBeacon(url, string)` (a `text/plain` request with the token in the body) arrived 5 of 5 in all three at one round trip; a `Blob` body was never sent by Firefox on a close (Firefox reads the body after the page is gone); an `application/json` body (a preflight) by none; a `fetch` with `keepalive` and an `Authorization` header also arrived, in two round trips. Send it only for `pagehide` with `persisted` false: a phone's app switch fires `visibilitychange` and no unload, and the back-forward cache fires `pagehide` with `persisted` true. To emulate a tab that is away, hold its requests (`route.fallback()` later), never abort them: a refused request is an error, and the game's own timeout (10 s) then decides when it polls again, so the probe measured the refusal, not the tab. Poll a rate-limited route no faster than its limit allows. Deadnight `tools/web_smoke/page_closing_transport.py` and `page_closing.py` (#1188). |

## A probe that can fail {#probes-that-can-fail}

A probe that passes on a night that never tested its case is worse than none. Each entry is a way one passed.

- **Approach:** Make a probe step that sets up a condition read it back and fail on a difference, and let the pass need
  the thing it tests: the bots asked for are counted in the result, a drag has distance to cover, a grenade is tried
  only once round 1 is on. Open the `result.json` of a first run and read the numbers that define the case before the
  checks. **Watch out for:** a tap that hits nothing logs nothing, so a "set seven bots" step changed nothing and the
  night passed with none; a bench placed the target 0.44 m off, under the 0.55 m stop, and the drag loop ended on its
  first check. **Seen:** Deadnight #490, 2026-11-02; Deadnight #1305, 2026-11-05 (fix: the probe reads `bots` and
  `players` back, and fails when the bench starts too near to need a drag or the night is paused).
- **Approach:** Run a "does it come back" probe on a build known to be broken first, with the link conditions the bug
  needs: a TCP relay in the probe that holds every chunk 100 ms each way, in order. **Watch out for:** the freeze probe
  ran on a client without the fix against a server on the same machine and every stall came back within 1.2 m, because
  the desync is a feedback loop that only runs away with a round trip of a few frames; loopback is under 2 ms and
  Chrome's network throttling does not apply to WebSockets. **Seen:** Deadnight #502, 2026-11-02 (fix: the relay; the
  old client flew off to 10^22 m, the fixed one stayed within 0.03 m).
- **Approach:** A probe that tests a time window stamps its taps with the page's own clock (`performance.now()` at
  every touch start and every effect), keeps the gaps short, and fails when the last tap meant to be inside the window
  started outside it. **Watch out for:** each tap through the DevTools protocol (start, hold, end, sleep) cost about 230
  ms of real time, so three taps "inside the 0.6 s cooldown" began 781 ms after the first and the game was right to
  let the third blow land; it looked like a tap queued during the cooldown. **Seen:** Deadnight #588, 2026-11-02 (fix:
  `stamp()` in `touch_melee.py`).
- **Approach:** Walk a probe to a control by its name, never by counted key presses or taps: the game publishes the
  focused control (`focus`), every control of a panel is named by its setting key, and the probe presses with a bound
  and fails naming the wanted control, the one reached and the ones passed. **Watch out for:** a parallel pull request
  added a control to the row, so the Rights changed the skill and left the bots at 0; Down from a slider lands on the
  nearer of two selectors that share a row; a tap spot on "the end of the row" hit the other selector; unnamed controls
  (`@UIOptionSelector@12`) cannot say where the focus is. **Seen:** Deadnight #730, 2026-11-03; Deadnight #743,
  2026-11-03; Deadnight #534, 2026-11-02 (fix: `focus_control(page, name, key)`; after a pull request adds a control to
  a screen, grep `tools/web_smoke` for the key walks of that screen).
- **Approach:** Before tapping a field, check that the box the game reports is on the page and scroll as a player
  would (a drag from the scroll area's margin) when it is not; a tap that must hit nothing uses one named spot that the
  screenshots show empty on every screen the probe visits, never a corner. After merging main, export the web build
  from the merged head before running the probes. **Watch out for:** a merge moved the code field to 101 % of a 390 px
  page, the tap landed off the page, and the "tap nothing" at `(40, 40)` hit the Play tab; a build exported earlier
  showed the field at 204 px and passed. **Seen:** Deadnight #1200, 2026-11-05 (fix: `scroll_into_view` and
  `EMPTY_SPOT`; no check was loosened).
- **Approach:** Give a browser probe a stub for what needs a user gesture (`requestPointerLock`) when the probe is not
  testing it, and count a page error as a problem only for what it tests. When the same error fails a second pull
  request, file it then instead of rerunning. **Watch out for:** a skin tour ended by starting a night; on a slow runner
  the grip's lock request came too long after the last key press and the browser refused it, so the step failed on
  `A user gesture is required to request Pointer Lock.`; it had been listed as a flake and nothing tracked it.
  **Seen:** Deadnight #1028, 2026-11-04 (fix: `skin_tour.py` stubs it as `activity.py` and `bot_wheel.py` did).
- **Approach:** Add a prompt or wait to a flow only after searching everything that enters it (`grep` the screen's
  class name, its route and its URL parameters in `tests/` and `tools/web_smoke/`); each unit test gives the player the
  state that skips the prompt and one test answers it, and a smoke answers the real prompt through a probe flag.
  **Watch out for:** every automated path arrives with a fresh profile, so a name asked at the first sign-in hung two
  GdUnit tests for the 5 minute timeout and would have hung `rooms.py` in CI; the change was tested through its own new
  tests only. **Seen:** Deadnight #485, 2026-11-02 (fix: the saved-name state in the tests, the `naming` probe flag).
- **Approach:** Give a probe the context of a control that shows only sometimes (`touch_strike`), and skip a circle
  the layout lists but does not draw; run a fit or clearance matrix twice, with the context down and up, hand a place
  search the cards that move, and add a new hint to every "first run" list in the commit that adds it. **Watch out for:**
  `touch_buttons` lists every circle, drawn or not, so a probe failed on a Strike button that was not there; a ticket-fit
  matrix had only run with it down; two expected lists lacked the new hint. **Seen:** Deadnight #1295, 2026-11-05 (fix:
  the flag in the probe and a grep of `touch_buttons` and `TouchHints.ORDER` in the tests and the probes).
- **Approach:** To lift one of two fingers in `Input.dispatchTouchEvent`, send a `touchEnd` that lists only that
  finger; check the game's held-button list before and after each variant of a touch sequence. **Watch out for:** a
  `touchMove` that lists only the finger that stays releases nothing, whatever the protocol text says, and a `touchEnd`
  with no points lifts every finger, so Aim stayed held after its tap and the sprint it should have returned to never
  came back. **Seen:** Deadnight, 2026-11-05 (fix: `second_finger_up` in `touch_sprint.py`).
- **Approach:** Take a picture of a night after the numbers, for a reader, with a long timeout and in a `try`
  (`page.screenshot(timeout=120_000)`); a check that reads a number never waits on a picture. **Watch out for:** a page
  drawing a night on the runner's software renderer can leave the compositor without a frame for over 30 s, so
  Playwright's default screenshot timeout failed `bridge_calls.py` on main after the counts were already in (the step
  took 161 to 187 s in six other runs). **Seen:** Deadnight #1235, 2026-11-05 (fix: `take_shot`, which notes a missed
  picture in the report).
- **Approach:** When a probe fails, read the failure against the page before the game: print what the page published,
  trace the state of each step in a debug script on the same export, then make the bench ready only when it can be
  driven (the touch layer is up, the button shows) and make the probe fail on its own reason. **Watch out for:** a
  function's default argument is bound when it is defined, so `export_bench(scene=BENCH_SCENE)` ignored a probe that
  set `BENCH_SCENE` later and waited 240 s on a page that never published the names; a bench called the night ready
  during the helicopter drop, when the touch layer is down, so every drag turned nothing. **Seen:** Deadnight #1317,
  2026-11-06 (fix: the scene is read at call time and the bench waits for a drivable layer).
- **Approach:** After a rework that touches several screens, run the whole phone probe list once on one export of
  main, read each failure against the game first, change the probe to the new fact, and never loosen a limit to get a
  pass. **Watch out for:** CI runs no browser probe, so each pull request ran its own on its own base and nothing ran
  the rest after the next one landed: four went stale (a Strike button that held `''`, a stick finger placed on what
  became the scoreboard, tablet snaps held to the phone's floors), and the game was right each time. **Seen:** Deadnight
  #1317, 2026-11-06 (fix: skip contextual buttons unless drawn, start the stick on free ground, leave the tablet out).

## Gates and timings on a shared runner {#gates}

A CI runner is a pool of machines, so the same build moves by 40 % and more between runs. A gate on a time has to be
calibrated on that spread, and what it cannot see needs a count that does not move with the runner.

| Topic | What we learned |
| --- | --- |
| A ratio gate and a change that moves its denominator | The night-load gate is the night's load over the same run's load to the menu (limit 5.5x, Deadnight #873). A change that made the menu 7 s quicker (it stopped redrawing the 3D stage while the page came up) failed it three times in a row on nights that were in the usual range for the runner: the quotient rose, the night did not. Before reading a red ratio as a slower night, put both terms beside `main`'s runs (`gh run view <id> --log`, the `night_load` block and `menu_frames`) and divide the night by something the change is unlikely to move; replay it locally with the two builds interleaved. When a change speeds up the term the gate divides by, the calibration is out of date, which is a maintainer's decision, never a quiet raise of the limit in the same pull request (Deadnight #966). |
| A frame time on a software renderer, compared | Frame times in SwiftShader moved by half or more (20 to 31 ms for one build) with whatever else the machine ran, so a before and after of two builds says nothing until it is in turns, many times. Count instead what the engine asks of WebGL in each frame (wrap `WebGL2RenderingContext.prototype.drawArrays`, `drawElements`, `clear`, `blitFramebuffer`, `bindFramebuffer`, `texImage2D`... for the seconds measured only and put them back: a wrapper on the whole night slows what a time gate reads): the counts do not move with the machine, so equal counts mean the two builds do the same work. The GPU process's CPU seconds (`SystemInfo.getProcessInfo` on a browser-level CDP session) are SwiftShader's threads spinning: 207 ms a frame whether the frame took 20 ms on 16 cores or 30 ms on 2, so it shows "the same", not "how much". To test a slower machine pin the whole run (`Start-Process -PassThru`, then `.ProcessorAffinity`: the browser inherits it) rather than `Emulation.setCPUThrottlingRate`, which slows only the page's main thread. Read one artifact before collecting 150: the path and the stats key were guessed once. Deadnight `tools/web_smoke/menu_idle.py`, `docs/research/web-export.md` "The idle menu after #920". |
| Hosted runners are several CPU models | A CI label (`ubuntu-24.04`) is a pool: the same web build's idle menu frame in SwiftShader was 60 ms on an AMD EPYC 9V45, 73 on an Intel Xeon 6975P-C, 80 on a 9V74, 98 to 100 on an EPYC 7763 and a Xeon 8573C and 119 to 121 on a Xeon 8370C, so a run's frame time says little until its machine is written beside it (the smoke records `machine`: CPU model, usable CPUs, load). To tell a change from the runners, run the builds before and after in turns on the same runners: a throwaway workflow (a push trigger on the branch, `paths` on itself) that downloads each commit's `web-build` artifact by id and runs the measure in a matrix of 20 to 24 jobs with `lscpu` printed; the same build then reads 60 to 120 ms between runners and the same on one, and a change shows within a runner (a 1 % step was seen in 15 of 20). A probe built for the A/B copies the gate's own steps before its window, or the older build reads 150 to 2 600 ms. To read many old runs, fetch `smoke/result.json` only (HTTP range requests on the artifact's signed address: 70 KB instead of 34 MB a run; Deadnight `tools/web_smoke/smoke_history.py`). |

- **Approach:** Set a time gate from the spread of many runs, not from one green run: take the mean of ten runs and a
  limit twice that, or 10 % over the worst of a hundred, and hold small rises by the recorded numbers and a count the
  runner cannot move. **Watch out for:** a gate at the last green run plus 75 % (52 s) failed a main run at 53.3 s,
  and ten main runs of one morning took 24.3 to 53.3 s; a later gate set from 28 runs failed 8 of the next 181
  healthy ones, because over 181 runs the same build's night varies 25 to 95 s and no number a run records
  (menu 0.58, idle frame 0.51, the night's frame 0.71 in log correlation) predicted it. **Seen:** Deadnight, 2026-11-02;
  Deadnight #966, 2026-11-04 (fix: baseline 36 s and limit 72 s, then a divisor floored at the menu's median, 14 s).
- **Approach:** Before promising that a gate catches a regression, replay the gate on runs of the regressed build
  (download the artifacts of 100 or more runs, `night_load.py --scale 1.5` makes the night 50 % longer) and count the
  failures at x1 and at x1.5, 2 and 3; a cost the gate cannot see is held by a count in a test. **Watch out for:** a
  ratio gate (limit 5.5, backstop 150 s) was asked to fail a build with the sound decode back behind the bar, but the
  28 runs it was set from already had it, and the decode is about 4 s of 40 against a spread of 2.2 to 4.6, so a ratio
  absorbs the runner's speed, not a small real cost. **Seen:** Deadnight #873, 2026-11-03; Deadnight #828, 2026-11-03
  (fix: the gate catches about an 80 % growth; `test_load_cost.gd` caps seconds decoded behind the bar).

## A bench's web export {#bench-web}

<!-- new section: every bench under a template's tools/bench/ repeated in its header how to put it in a web build, and
each bench author worked it out again (#963, #1059, #1062) -->

A template's benches (`tools/bench/<name>.tscn`, most with a `<name>.py` that reads the result in Chrome) measure in
the web build what the desktop numbers cannot. The web build starts the menu and leaves `tools/*` out of the pack, so a
bench runs from a throwaway game, and one command makes it, from your worktree:

```text
uv run --project <your worktree>/python gds template bench-web 3d-third-person nav_cost_bench
uv run --project <your worktree>/python gds template bench-web 3d-third-person nav_cost_bench --run --probe-args=4
```

It makes the game from the working tree's template in a workspace of its own (as `gds template game`, see [Proving a new
game](new-game.md#proof)), sets `run/main_scene` in its `project.godot` to the bench, takes `tools/*` out of the Web
preset's `exclude_filter` (the tests and addons stay out), exports with the pinned Godot (`--export-release Web`,
failing on an `ERROR` line; an export whose only error is the at-exit leak runs once more, as CI does) and prints the
build's folder, the game and the probe's command. The bench is named by its name, its `tools/bench/<name>.tscn` path or
its `res://` path; any scene of the game works by its path (`tools/soak/ai_soak.tscn`), since only a bare name is looked
up in `tools/bench/` and every `tools/*` folder goes into the pack. Without `--run` the game is kept (`gds template
clean <path>` when done); with `--run` the bench's `<name>.py` reads the build under `gds quiet` (`--probe-args` after
the build folder: 4 is the weak-machine throttle) and the game is removed unless `--keep`, the exit code the probe's.
Nothing in the template changes. Its tests are `python/tests/test_bench_web.py` (the edits on the real template files, a
fake Godot).

Through it, the nav cost bench of 3D Third Person read 189, 267 and 562 µs a tick for 50, 100 and 200 navigators in
headless Chrome on a workstation, and the hit zones bench ran with `--run` (gdstudio #1130).

- **Approach:** Count a web bench in physics ticks (`Engine.get_physics_frames()`), not in rendered frames, and run it
  for 900 ticks or more when it reads a part's mean; to time a bench by part, add `Time.get_ticks_usec()` spans in the
  kept game (`bench-web` without `--run`), export it again and read the means. **Watch out for:** a headless Chrome
  page draws about three frames per physics tick at 1x, so a row of 300 frames held about 100 ticks; and the browser's
  clock steps at 100 µs, so a span of 20 to 150 µs averages to a usable mean only over many hundreds of samples.
  **Seen:** gdstudio #1104 (PR #1209), 2026-11-11.
- **Approach:** For a before and after in Chrome, make two builds of the same bench: `bench-web` from your worktree
  and from a checkout of `main` (`--project <main checkout>/python`; a bench new to the branch is copied into main's
  kept game and exported again), then run the two probes in turns, A B A B, on a quiet machine. **Watch out for:** one
  build measured at two times compares two machine loads, which moved rows 15 to 20 % between runs, more than most
  changes save. **Seen:** gdstudio #1208 (PR #1219), 2026-11-11.
- **Approach:** Build a bench's figures from the bodies the template ships, named by an argument (`hold_cost.tscn --
  rifle male`, `?body=male`), and when the template's bodies or a part's per-body data change, check that the bench's
  model paths still name them before you compare numbers. **Watch out for:** the hold bench kept loading the
  Quaternius mannequin after the template moved to its own bodies (#1299) and the rifle's hold gained per-body fits
  (#1040), so a before and after measured a body no character wears and never the male's fit. **Seen:** gdstudio
  #1178 (PR #1258), 2026-11-11.
- **Approach:** Give a bench's new script its `.uid` (`gds template uids <t>`) before the first `bench-web` run, and run
  `gds template test <t>` before the push. **Watch out for:** `bench-web` exports without the layout check, so a bench
  whose script had no `.uid` measured fine, and the missing file showed only when the full run's layout check stopped
  it. **Seen:** gdstudio #1186 (PR #1268), 2026-11-11.
- **Approach:** To measure a branch with a probe that exists only in another open pull request, merge both branches into
  a throwaway worktree (under `worktrees/`, from `origin/main`), run `bench-web` from it, name the other pull request in
  the body, and remove the worktree after. **Watch out for:** neither branch alone held both the change and the probe
  that shows it, and nothing here said how to measure one with the other. **Seen:** gdstudio #1247 (PR #1250, with the
  soak probe of PR #1248), 2026-11-11.
- **Approach:** To find where a part's web time goes, copy the kept game into your scratch folder at once, then turn
  one part off at a time by an address argument (`?exp=nopush`) or time parts with `Time.get_ticks_usec()` spans,
  export it again and read it in Chrome, each change against the build before it in turns, three rounds or more.
  **Watch out for:** running a part ten more times a frame read the hold's place at 16 microseconds a character where
  turning it off saved 34 (warm data, an early return the first run made possible); each span's clock read is a call
  into JavaScript (about a microsecond); one round each moved a row 5 to 10 microseconds. **Seen:** gdstudio #1347,
  2026-11-12 (the kept game in the temporary folder was gone between two exports).
- **Approach:** In a before and after of two builds, swap which build runs first in each round (A B, then B A), and
  read the median of the rounds. When the bench's own probe takes the pair of runs to compare as an argument (the
  fourth of `gait_cost.py`: `off,on` by default, `lean_off,on` for the lean alone), compare one part in one build
  rather than two exports. **Watch out for:** with `main` always first on a busy machine the branch read 3 to 9
  microseconds higher on code that adds about 0.2, and single rounds moved up to 20. **Seen:** gdstudio #1348 (PR
  #1393), 2026-11-12; #1403 (PR #1458), 11-13 (the pair argument).
- **Approach:** Before planning a web measurement on a bench, check what its probe reads: not every bench has a
  `<name>.py` for `--run`, and some probes measure another thing than a cost. **Watch out for:** `effects_cost.tscn`
  has no `effects_cost.py`, and `effects_first_use.py` counts the programs linked and reports Chrome's steady frame
  rate, so it cannot resolve an effect's cost under about 0.03 ms. **Seen:** gdstudio #1341 (PR #1383), 2026-11-12.
- **Approach:** Pass a bench's probe what it needs besides the build with `--probe-args` (they follow the build
  folder), and read what the game writes (a log, a result file) from a run kept with `--keep`. **Watch out for:**
  `--run` starts the probe with the build folder alone (`bench_web.probe_command`) and removes the game when it ends,
  so a probe that looked for the game's folder or options of its own found neither. **Seen:** gdstudio #1270 (PR
  #1301), 2026-11-11.
- **Approach:** Try a part's variants headless on the desktop first: the same kept game, `Time.get_ticks_usec()` spans
  per part printed by the bench, and the part called N times a frame (its span over N) so a change of a microsecond
  shows; then confirm the one kept in Chrome against `main`, in turns. **Watch out for:** an export and a Chrome round
  take minutes, a desktop run 15 seconds; the desktop's spans read the rifle hold's parts within 10 to 25 % of the web
  build's (the stance 26 against 28 microseconds, the push 8.9 against 8.9), but single runs on a busy machine still
  moved 15 %. **Seen:** gdstudio #1347, 2026-11-13 (eleven variants of the push in an hour).
