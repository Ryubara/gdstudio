# Web export: testing the browser build

What running the web build of a game in a headless browser taught us. The setup is Deadnight's web smoke
(`tools/web_smoke/smoke.py` there, Playwright driving the export); the game write-up is its
`docs/research/web-export.md`.

**Run every local browser probe through `gds quiet`** (Windows): under pointer lock headless Chrome confines the real
cursor of the person at the machine to its hidden window at the top left of the screen, until Esc ([no focus](no-focus.md#browser-probes-and-any-other-program-gds-quiet)):

```text
uv run --project <kit>/python gds quiet -- uv run --with playwright==1.64.1 python tools/web_smoke/<probe>.py <args>
```

A hook refuses a `tools/web_smoke/*.py` or Playwright run without it. CI runners have nobody at the machine; the
command is the same there (off Windows it starts the program normally).

| Topic | What we learned |
| --- | --- |
| Pointer lock clips the real cursor | Headless Google Chrome (`channel="chrome"`) under pointer lock clipped the person's cursor to `(17, 68, 864, 541)` for the whole lock; Playwright's default headless shell did not clip. `gds quiet` frees it every 5 ms: 0 of 777 samples held ([lesson](../../lessons/2026-11-02-a-headless-browser-under-pointer-lock-held-the-cursor.md)). |
| Pointer lock in headless Chromium | It works (`document.pointerLockElement` is the canvas after the click that starts the night), but on Linux, the CI runner, every synthetic `page.mouse.move` under lock arrives as a motion and then the opposite motion (+15 px, -15 px), which cancel. Windows does not do it. A smoke that must turn the view dispatches `new PointerEvent('pointermove', {movementX, bubbles: true})` on the canvas: Godot's web runtime listens for `pointermove` and reads `movementX/Y`. Check mouse look on the CI runner, not only on your own machine. |
| Key taps | Godot reads input once per frame, so a tap shorter than a frame can be lost: hold keys for about 150 ms. |
| Focus after Back | After Back from a screen nothing has focus; the router spends the first arrow or accept key giving it focus. |
| Touch is a mouse too | Godot's web runtime turns every window `pointermove` into a mouse motion in device pixels, and a touch pointer fires `pointermove` as well, so each finger also turns a mouse-look camera (three times too far at a pixel ratio of 3). Stop touch `pointermove` in a capture-phase listener in `html/head_include` and prove phone input in a mobile-emulated Chrome with `Input.dispatchTouchEvent`, not with synthetic `InputEventScreenDrag` on desktop ([lesson](../../lessons/2026-11-02-a-finger-is-a-mouse-motion-too-in-the-web-runtime.md)). |
| A new prompt in a flow | A prompt or wait added to a flow (a name asked at the first sign-in) changes every automated path through it: unit tests that call the screen and every web smoke that drives it start from a fresh profile and stop at the prompt, until the 5 minute test timeout or the smoke's wait. Search the screen, its route and its URL parameters in `tests/` and `tools/web_smoke/` and update each in the same change; a smoke answers the real prompt through a probe flag ([lesson](../../lessons/2026-11-02-a-new-prompt-hung-every-test-and-smoke-that-passed-through-it.md)). |
| A ratio gate and a change that moves its denominator | The night-load gate is the night's load over the same run's load to the menu (limit 5.5x, Deadnight #873). A change that made the menu 7 s quicker (it stopped redrawing the 3D stage while the page came up) failed it three times in a row on nights that were in the usual range for the runner: the quotient rose, the night did not. Before reading a red ratio as a slower night, put both terms beside `main`'s runs and divide the night by something the change is unlikely to move (the idle menu's mean frame, `menu_frames.mean_ms`, tracked the night: 0.4 to 0.8 s per ms on `main`, 0.4 to 0.9 on the failing runs) ([lesson](../../lessons/2026-11-04-a-faster-menu-failed-a-gate-that-divides-by-the-menu-load.md)). |
| A script's answer is an int | `JavaScriptBridge.eval` hands a script's `true` back as the integer 1. `answer == true` is then an invalid operation, which a release build stops the function at without a word (no error in the console); a value meant to be cached was asked of the page again at every read (about 5 evals a second, Deadnight #983). Read an answer with `bool(answer)` or `int(answer)` ([lesson](../../lessons/2026-11-04-a-cached-answer-was-asked-again-because-eval-returns-an-int.md)). |
| A frame time on a software renderer, compared | Frame times in SwiftShader moved by half or more (20 to 31 ms for one build) with whatever else the machine ran, so a before and after of two builds says nothing until it is in turns, many times. Count instead what the engine asks of WebGL in each frame (wrap `WebGL2RenderingContext.prototype.drawArrays`, `drawElements`, `clear`, `blitFramebuffer`, `bindFramebuffer`, `texImage2D`... for the seconds measured only and put them back: a wrapper on the whole night slows what a time gate reads): the counts do not move with the machine, so equal counts mean the two builds do the same work. The GPU process's CPU seconds (`SystemInfo.getProcessInfo` on a browser-level CDP session) are SwiftShader's threads spinning: 207 ms a frame whether the frame took 20 ms on 16 cores or 30 ms on 2, so it shows "the same", not "how much". To test a slower machine pin the whole run (`Start-Process -PassThru`, then `.ProcessorAffinity`: the browser inherits it) rather than `Emulation.setCPUThrottlingRate`, which slows only the page's main thread. Deadnight `tools/web_smoke/menu_idle.py`, `docs/research/web-export.md` "The idle menu after #920". |
| Hosted runners are several CPU models | A CI label (`ubuntu-24.04`) is a pool: the same web build's idle menu frame in SwiftShader was 60 ms on an AMD EPYC 9V45, 73 on an Intel Xeon 6975P-C, 80 on a 9V74, 98 to 100 on an EPYC 7763 and a Xeon 8573C and 119 to 121 on a Xeon 8370C, so a run's frame time says little until its machine is written beside it (the smoke records `machine`: CPU model, usable CPUs, load). To tell a change from the runners, run the builds before and after in turns on the same runners: a throwaway workflow (a push trigger on the branch, `paths` on itself) that downloads each commit's `web-build` artifact by id and runs the measure in a matrix of 20 to 24 jobs with `lscpu` printed; the same build then reads 60 to 120 ms between runners and the same on one, and a change shows within a runner (a 1 % step was seen in 15 of 20). To read many old runs, fetch `smoke/result.json` only (HTTP range requests on the artifact's signed address: 70 KB instead of 34 MB a run; Deadnight `tools/web_smoke/smoke_history.py`) ([lesson](../../lessons/2026-11-04-ci-runners-are-six-cpu-models-and-the-smoke-recorded-none.md)). |
| A saved file in a browser run | A web export keeps `user://` in the page's IndexedDB: database `/userfs`, object store `FILE_DATA`, one record a file under `/userfs/godot/app_userdata/<project name>/<file>`, its bytes in `contents` (`new TextDecoder().decode(record.contents)`). A run proves that a file survives a reload by reading it there with `page.evaluate` (list the store's keys when the path is wrong: the project name is part of it), reloading the same context (a new context has empty storage) and reading what the game found again through `window.deadnight`; the write is mirrored from the page a moment after the file is closed, so poll for it. Two traps met on the way: Deadnight's `smoke.probe` returns only the keys the older probes read, so a new probe key is read with `Object.assign({}, window.deadnight)` (as `lobby.py` does), and a lobby the first visit made is still held by the backend after the reload (409 `already_in_lobby`: leave it first). Deadnight `tools/web_smoke/guest_account.py` (#1080). |
| A probe that needs the rules to say yes | A grenade, a purchase or a revive is refused until the first round is on, and a solo night is in its intro for a while after `running` is true ("ROUND 00"): the client goes on drawing a preview of what the server refused. Wait for `round >= 1` and read the server's own word through the probe (`grenade_cooking`: `GrenadeServer.is_cooking`), never the picture ([lesson](../../lessons/2026-11-05-a-browser-probe-held-the-grenade-before-the-first-round.md)). Deadnight `tools/web_smoke/touch_weapon_places.py` (#1280). |
| A last request when the page closes | A `fetch` or beacon sent from `pagehide` is proved by closing a real tab (`page.close()`) in Chromium, Firefox and WebKit, against a deployed backend or a proxy that holds each request 150 ms. `sendBeacon(url, string)` (a `text/plain` request with the token in the body) arrived 5 of 5 in all three at one round trip; a `Blob` body was never sent by Firefox on a close; an `application/json` body (a preflight) by none; a `fetch` with `keepalive` and an `Authorization` header also arrived, in two round trips. Send it only for `pagehide` with `persisted` false: a phone's app switch fires `visibilitychange` and no unload, and the back-forward cache fires `pagehide` with `persisted` true. To emulate a tab that is away, hold its requests (`route.fallback()` later), never abort them. Deadnight `tools/web_smoke/page_closing_transport.py` and `page_closing.py` (#1188) ([lesson](../../lessons/2026-11-05-a-beacon-with-a-blob-body-was-never-sent-by-firefox-on-close.md), [lesson](../../lessons/2026-11-05-a-quiet-tab-emulated-by-refusing-requests-measured-the-refusal.md)). |
| Which GPU | The browser masks the adapter from Godot; read `UNMASKED_RENDERER_WEBGL` (`WEBGL_debug_renderer_info`) through `JavaScriptBridge` to spot SwiftShader and fall back to a cheaper scene ([lesson](../../lessons/2026-11-02-a-browser-masks-the-gpu-from-godot.md)). |

## Pointer lock and Esc, from the first night {#pointer-lock-and-esc-design-it-in-from-the-first-playable-night}

A browser owns the Esc key while the pointer is locked. The first Esc exits pointer lock and never reaches the game;
Godot gets no `pause` press. A game that pauses only on its `pause` action therefore keeps running with a free cursor:
mouse motion still turns the view (the cursor runs into the screen edges), a click fires the weapon, and only a second
Esc opens the menu. Every web game with mouse look has this, so it is part of the first playable night, not polish.

- **Pause on lock loss, not on the key.** When the game expects the mouse captured and the real mode is no longer
  `Input.MOUSE_MODE_CAPTURED` (the web display server reports the browser's pointer-lock state), open the pause menu in
  that same frame. Treat a lost window focus the same way. Esc then opens the menu once, on desktop and on the web.
- **Nothing drives the game while unlocked.** No mouse-motion look and no fire from a click until the lock is back.
- **Re-lock from a click.** Browsers grant pointer lock only inside a user gesture: Resume is a button press, and the
  capture call runs in its handler. After leaving lock, Chrome refuses a new lock for about a second; show the menu,
  never retry in a loop.
- **Test it in the browser.** A GdUnit test can set the mouse mode out from under the player; the web smoke must also
  release pointer lock in headless Chromium (`document.exitPointerLock()`) and check the pause screen is up.
- **What the engine reports.** On the web, `Input.mouse_mode` reads the real pointer-lock state (captured while
  locked, visible once freed), so poll it each frame. A headless Godot reads the mode back as visible whatever was
  set, so unit tests put a stand-in platform under the grip. Playwright cannot press the browser's own Esc: release
  with `document.exitPointerLock()`. Measured in Deadnight #481: the menu was up 0.6 s after the release.

- **A bench that has no mouse withdraws the request, not only the mode.** A browser probe's test scene that sets the
  mouse mode to visible after the player asked for the lock reads as a lock lost: the night pauses, the touch layer
  goes dead and a look drag never turns the view (Deadnight #490). The bench drops the player's request
  (`grip.want(false)`), and the probe reads `paused` from the page, so the cause is in its message.

Lesson: [Esc in the browser freed the cursor but did not pause the game](../../lessons/2026-11-02-esc-in-the-browser-freed-the-cursor-but-did-not-pause.md).

- **Approach:** In a web game with mouse look, pause on the loss of pointer lock (or focus), not on the key; ignore look
  and fire while unlocked, re-lock from a button press, and have the web smoke release the lock and check the pause
  screen. **Watch out for:** in a browser the first Esc only exits pointer lock and never reaches the game, so the
  game's `pause` key never came and mouse look and fire kept running with a free cursor. **Seen:** Deadnight, 2026-11-02
  (fix: the pause follows the lock, as above; it belongs in a web game's first design).

## Discord Activity: the proxy and the iframe {#discord-activity-the-proxy-and-the-iframe}

A Discord Activity is the web build in an iframe on `<id>.discordsays.com`, reaching outside hosts only through its
URL mappings. A build that works in a browser tab can fail there in three silent ways (Deadnight #469, #475, #479):

- **The mapping keeps its prefix.** `/api` mapped to the backend forwards `/api/auth/guest` unchanged: serve the routes
  with and without the prefix ([lesson](../../lessons/2026-11-02-discord-activity-proxy-keeps-the-mapping-prefix.md)).
- **Answers come gzipped and are decoded twice.** The browser decodes them but keeps `Content-Encoding: gzip`, and
  Godot's `HTTPRequest` decodes again and fails with status 0, while the server logged 200. Set
  `HTTPRequest.accept_gzip = false` in the web build, and trade an OAuth code once
  ([lesson](../../lessons/2026-11-02-a-godot-web-client-decoded-gzip-twice-behind-a-proxy.md)).
- **No focus, no gamepad.** The iframe starts without the focus, and Chromium lists no pad to it until the player
  clicks in it and presses something; Godot swallows the error. Focus the window and canvas on the first pointer or
  key event, and tell the player on screen to click once
  ([lesson](../../lessons/2026-11-02-an-activity-iframe-lists-no-gamepad-until-a-click.md)).

An agent cannot open an Activity, so stand one in before asking the maintainer to try: a local HTTPS host for
`<id>.discordsays.com` (Chrome `--host-resolver-rules`) that keeps the prefix and gzips its answers, an iframe of
another origin, a parent that keeps the focus, a virtual pad (Deadnight `tools/web_smoke/activity.py`, under
`gds quiet`). Walk sign-in, lobby, ticket and WebSocket through it, test focus in a headed browser (headless Chromium
reports the focus as held), and read the backend log of the maintainer's first try. Test runs with fresh instance ids
hold game-server slots until they are swept, so use few per run. A CI deploy of `main` replaces a hotfix deployed from
a branch: check `railway deployment list --service web` before the maintainer retries.

- **Approach:** Give anything that covers the screen an exit for every way its wait can end, tested with the cover on,
  and prove a join inside the Activity itself: a native or web probe does not pass through Discord's proxy. **Watch out
  for:** a failed join was only ever read as a signal in headless tests; on screen the loading overlay stood over the
  failure card and the join reported no step, so creating a match from the lobby looked like a hang. **Seen:**
  Deadnight #1366, 2026-11-06 (fix: tracked in Deadnight #1366; no check yet finds a cover without an exit).
- **Approach:** Before asking the maintainer to try an Activity, run the web build behind the real
  `<id>.discordsays.com` host or a local HTTPS stand-in that keeps the prefix and gzips, through sign-in, lobby, ticket
  and WebSocket, and read the backend log of the first try. **Watch out for:** the Activity was declared ready from
  browser tests only: the URL mapping keeps its prefix (404, #469), and the proxy's gzip was decoded twice by
  `HTTPRequest`, so every answer read as status 0 while the backend logged 200 (#475) and the game resent the OAuth code
  (`invalid_grant`). **Seen:** Deadnight, 2026-11-02 (fix: routes served with and without the prefix, `accept_gzip =
  false` on web, an OAuth code traded once (above)).
- **Approach:** Test an embedded web build from an unfocused start in a headed browser (headless Chromium fakes the
  focus), tell the player on screen to click once, prove the pad after a click, and make a failure the engine swallows
  visible in the probe line. **Watch out for:** the Activity's frame starts without the focus, Chromium lists no pad
  until the frame has focus and sees an input, and Godot's web runtime catches the error, so the pad worked only after a
  click and a stick move, and the probe could not tell "never tried" from "tried and failed". **Seen:** Deadnight #479,
  2026-11-02 (fix: deadnight #482
  ([lesson](../../lessons/2026-11-02-an-activity-iframe-lists-no-gamepad-until-a-click.md))).
- **Approach:** Say something happened only after the host says so; a harness that fakes a host answers as the host can
  (refused, unauthenticated, missing scope, an error object, silence) and runs the real SDK handshake, and a platform
  fix is proven in the real client before its issue closes. **Watch out for:** the share button claimed Discord's picker
  opened whatever Discord answered, while the stub always said yes; the first fix passed, but the bridge never called
  `authenticate`, so Discord refused `shareLink` with RPC 4006. **Seen:** Deadnight #627, 2026-11-02; Deadnight #627,
  2026-11-03 (fix: deadnight #649, then the handshake
  ([lesson](../../lessons/2026-11-03-a-harness-that-faked-the-hosts-answers-passed-a-refusal-it-never-met.md))).

## Discord Activity: copy and paste in the frame {#discord-activity-copy-and-paste-in-the-frame}

Text in and out of the game (a room code, a link) is a permission of the host page, not a given (Deadnight #516):

- **No clipboard API.** In an iframe of another origin `clipboard-read` and `clipboard-write` are Permissions-Policy
  features that default to `self`: `navigator.clipboard.writeText/readText` throw `NotAllowedError`
  (`document.permissionsPolicy.allowsFeature` is `false`). Godot's `DisplayServer.clipboard_set/get` are exactly those
  calls and fail silently, so a "Code copied." message is a claim, not a result. `document.execCommand("copy")` from a
  user gesture still works (it is not policy-controlled).
- **Ctrl+V never pastes.** Godot 4.7's web runtime calls `preventDefault()` on every canvas `keydown`, so the browser
  never fires the `paste` event (the one that needs no permission). Its own paste is async `readText`: denied in the
  frame, and stale on the first press elsewhere.
- **Fix shape.** A capture-phase window `keydown` for Ctrl/Cmd+V that calls `stopImmediatePropagation()` (not
  `preventDefault()`), a `paste` listener that hands `clipboardData` to the game (Chromium fires `paste` on a focused
  non-editable canvas), copy through a hidden textarea and `execCommand`, and native Ctrl+C through the same textarea
  focused during the keydown. Show "copied" only when the page confirms, and show the text selected when nothing works.
- **Share without the clipboard.** The SDK's `commands.shareLink({message, custom_id})` (no scope; returns
  `success`, `didCopyLink`, `didSendMessage`) sends a link with text through Discord's own window; `openInviteDialog`
  invites to the channel. `shareLink` answers when its window is **closed**, not when it opens; it rejects with a plain
  `{code, message}` object (`String(error)` is "[object Object]"), and a reply the SDK cannot parse is logged
  (`Failed to parse`) and leaves the promise pending for ever. Show a "pick who to send it to" hint only while the
  command has not been refused, say so when it was, and keep the raw `message` frame for a probe line (Deadnight #627).
- **`shareLink` needs an authenticated Activity.** "No scopes required" is about OAuth scopes: Discord's client
  refuses `shareLink` and `openInviteDialog` with RPC error 4006 ("Not authenticated or invalid scope") until the
  Activity has run `authenticate({access_token})`. The flow: `ready`, `authorize` (a code), the backend swaps the code
  for a token with the client secret, `authenticate` with the token (Deadnight #627, second fix). The harness for
  such a feature runs the real SDK against a fake client that enforces this order (Deadnight
  `activity.py --share --real-bridge`).
- **Test it** in Playwright with a cross-origin iframe, in the headless shell (its clipboard is the browser's own,
  never the person's), `context.grant_permissions` for the parent origin and a
  `permissions-policy: clipboard-read=(), clipboard-write=()` header on the frame (Deadnight
  `tools/web_smoke/activity.py --embed clipboard-denied --clipboard`, under `gds quiet`).

- **A tab has the stale first Ctrl+V too** (Deadnight #534). The `paste` event needs no permission, so the paste half
  of the layer (the capture-phase Ctrl/Cmd+V that lets the key reach the browser, the `paste` listener) belongs in every
  web context; only the copy half (hidden text box, native Ctrl+C) is a frame's, a tab's own `clipboard_set` works from
  the press. Walk a probe to a control by its name, never by counted key presses.

Lesson: [Copy and paste did nothing in the Discord Activity](../../lessons/2026-11-02-an-activity-frame-could-not-copy-or-paste.md).
Lesson: [The first Ctrl+V in a browser tab pasted nothing](../../lessons/2026-11-02-the-first-ctrl-v-in-a-browser-tab-pasted-nothing.md).
Lesson: [Share in Discord said "Pick who to send it to" and Discord opened nothing](../../lessons/2026-11-02-a-share-button-said-pick-who-to-send-it-to-whatever-discord-answered.md).
Lesson: [A harness that faked the host's answers passed, and the real host refused with 4006](../../lessons/2026-11-03-a-harness-that-faked-the-hosts-answers-passed-a-refusal-it-never-met.md).

- **Approach:** Run any feature that moves text in or out of the game (codes, names, links) in the Activity iframe
  harness with a denying policy, and show a "done" message only after the platform confirms the result. **Watch out
  for:** the clipboard is a permission of the host: a cross-origin iframe has no clipboard API by default and Godot's
  web runtime cancels every canvas `keydown`, so Ctrl+V made no `paste` event, and the screen said "Code copied."
  without checking. **Seen:** Deadnight #516, 2026-11-02 (fix: the paste and copy layer of this section (Deadnight #533,
  [lesson](../../lessons/2026-11-02-an-activity-frame-could-not-copy-or-paste.md))).

## Discord Activity: the same game as the website {#activity-same-game}

<!-- new section: the Activity sections cover the proxy and the frame; none says the Activity behaves as the
website does -->

- **Approach:** Give the Discord Activity the website's flow at every step: it opens on the main menu, Play together
  shows the code field and the create button, and nothing is made until the player presses; search every platform branch
  (`instance_id`, `in_discord()`) and remove what a press does there and not on the website, unless the maintainer
  asked. **Watch out for:** a launch went straight to Play together without asking; the fix moved the first screen and
  kept the shortcut behind it, a lobby per instance id, so a second player got a lobby of their own. **Seen:**
  Deadnight #495, 2026-11-02; Deadnight #1178, 2026-11-05 (fix: a platform identity is never a room key; a test
  fails on any lobby request from the Activity's screen
  ([lesson](../../lessons/2026-11-05-a-platform-shortcut-outlived-the-fix-that-moved-its-first-screen.md))).

## A phone's keyboard in the web build {#a-phones-keyboard-in-the-web-build}

A `LineEdit` opens a phone's keyboard through a hidden `<input>` the engine focuses (Godot 4.7.2,
`platform/web/js/libs/library_godot_display.js`, `GodotDisplayVK`). Deadnight #1183: nobody could type a room code on a
phone, in a browser or in the Discord Activity.

- **The export option is the switch.** `html/experimental_virtual_keyboard` (default off) is
  `GodotDisplayVK.available()`; off, `DisplayServer` has no virtual keyboard feature, `LineEdit` never asks for one and
  the page has no `focus()` call at all. Check it from the page, not from the game: a tap on a field with the option off
  leaves `document.activeElement` on the canvas.
- **The option alone is not enough for a phone.** The engine focuses its input from the first touch event
  (`touchstart`); iOS raises a keyboard only for a focus made in the events that lift the finger (`touchend`, `click`).
  Hold a focus that `window.event` says came from `touchstart` or a touch `pointerdown` (wrap
  `HTMLElement.prototype.focus` for the engine's own inputs: the ones with `z-index: -1` beside the canvas) and make it
  in `touchend` or `pointerup`. The engine's input has no `font-size`: under 16 px iOS zooms the page in and leaves it
  zoomed, so give inputs `font-size: 16px`. When the keyboard closes (`focusout` of the input) give the canvas the
  focus back and `scrollTo(0, 0)`.
- **Nothing moves the field above the keyboard.** A browser covers the bottom of the page and the engine does not know
  (`visualViewport.height + offsetTop` against `innerHeight`; a webview that resizes for the keyboard resizes the
  canvas instead, and the whole game then shrinks to the small page). Move the scene, not the layout, and hold it while
  a finger is down: a press on a button takes the field's focus and so the keyboard, and a scene that slides back at
  once leaves the lift of the finger beside the button. A `CanvasLayer` (the router's) ignores the root viewport's
  `canvas_transform`; move its `offset`.
- **A touch arrives as a mouse first.** In the web runtime the mouse press the engine makes of a touch
  (`device == InputEvent.DEVICE_ID_EMULATION`) reaches the game before the `InputEventScreenTouch`, so a field that
  takes the focus on that press sees `UIInputMode.touch` still false. Decide "a finger did this" from the press itself.
  The engine's own typing (the arrow keys it sends to place the caret) also marks the input mode as a keyboard.
- **What an emulated browser proves.** Chromium draws no keyboard. Read "up" as an editable `<input>` holding the
  focus, made inside a tap's event; stand in for the keyboard's height by shrinking `visualViewport` (a `Proxy` over
  the real one) or the viewport itself. A real keyboard, iOS Safari and Discord's webview need a real phone: say so in
  the pull request and give the steps. Deadnight `tools/web_smoke/phone_keyboard.py`.
- **When the keyboard cannot be proved, give the field a keypad.** A room code is 36 symbols: an on-screen keypad in a
  canvas layer of its own, with keys that take no focus (the field keeps it, so a hardware keyboard and Ctrl+V still
  work), needs nothing from the browser. Size it in CSS pixels (`PageSize.css_per_pixel`, 44 or more for a key), not in
  units and not in window pixels: a unit is 0.72 CSS px on a phone page since #1197 (it was 0.36, because the phone rule
  read the canvas), and a window pixel is half a CSS pixel at the capped ratio of 2.

- **Approach:** Run a flow that needs text (a code, a name, an address) with a finger on a phone-shaped page: the
  keyboard opens within the tap, the field stays above it and it closes cleanly; give a code a keypad that needs nothing
  from the browser, and say in the pull request what an emulated browser cannot show, with the steps for one real-phone
  check. **Watch out for:** a text field is an input device whose keyboard is the host's: the export had
  `html/experimental_virtual_keyboard=false`, the engine focuses from `touchstart`, its input is under 16 px, and every
  test typed with key events, so no keyboard opened on a phone. **Seen:** Deadnight #1183, 2026-11-05 (fix: the focus,
  font and keypad work of this section
  ([lesson](../../lessons/2026-11-05-a-phone-could-not-open-a-keyboard-in-the-web-build.md))).

## A phone page's size: the canvas is not the page

The canvas of a web page is its CSS size times the pixel ratio the page reports to the engine, and the game caps that
ratio at 2 on a touch device (`PhoneRender`, `html/head_include`): an 844 x 390 page is a 1688 x 780 window, a
932 x 430 page 1864 x 860 (Deadnight #1197).

- **Ask the page, not the window, what a person holds.** `Window.size` is device pixels. The CSS size is the canvas
  element's `getBoundingClientRect()` (`PageSize`), which is right inside an iframe too (Discord's Activity reports the
  frame's size). `matchMedia('(pointer: coarse)')` says a finger (`TouchMode.detect`). A phone is a touch device whose
  page's short side is under 500 CSS px, or any window whose own short side is under 500 (a native window, a small
  desktop window at ratio 1: as it always was).
- **The layout does not depend on the ratio.** The content scale factor multiplies the base stretch, which divides by
  the same window: an 844 x 390 window, a 1688 x 780 canvas and a 2532 x 1170 one all lay the menu out on 1169 x 540
  units. Only the pixels in each unit differ (0.72 CSS px per unit on all three).
- **Probe it on the page.** `tools/web_smoke/phone_layout.py` walks the menu screens in Chromium as a phone (and in
  an iframe with `--iframe`) and prints the page, canvas, factor, units and the smallest text and tap target in CSS
  px (`window.deadnight_audit`; `WebProbe`'s `layout`, `phone` and `ui_audit`). Run it through `gds quiet`.

- **A report that the game looks zoomed in on a phone is answered on the phone first.** Deadnight #1310: headless
  Chrome as a phone showed nothing wrong (canvas = page, visual viewport scale 1, a pinch and a double tap change
  nothing), so a fourth emulation would have said the same. Put the page's own numbers on screen behind a query
  (`?viewcheck`: `innerWidth`, `visualViewport` scale and offset, the pixel ratio real and reported, the canvas's box
  and pixels) and ask for a screenshot of it. Facts the emulation did give: the engine polls `innerWidth` and
  `innerHeight` every frame (`_godot_js_display_size_update`), so a turned page or an address bar changing the height
  needs no `resize` event to be followed; Chrome honours `user-scalable=no` and `touch-action: none` (each alone holds a
  pinch at scale 1, checked against a plain page that zooms to 5); iOS Safari ignores `user-scalable=no` and only a
  device shows the rest. `Input.synthesizePinchGesture` does nothing in headless emulation, even on a plain page: pull
  two points apart with `Input.dispatchTouchEvent` (`tools/web_smoke/phone_view.py` in Deadnight). Playwright's WebKit
  with an iPhone descriptor (`p.devices['iPhone 14 landscape']`) is the nearest engine to Safari here and is not Safari:
  `(pointer: coarse)` is true and `devicePixelRatio` is an own, configurable accessor (the ratio cap installs), but
  `navigator.maxTouchPoints` is 0 where an iPhone's is 5, so a touch test that asks for more than 0 (`TouchMode.detect`)
  runs the desktop path: add an init script that defines it as 5. There is no CDP session (no raw pinch) and no real
  toolbars or safe areas, so Safari's own zoom, `visualViewport` and `100dvh` are read on a phone (`?viewcheck`), not
  here.

## The live build {#live-build}

<!-- new section: the page is about testing the browser build; nothing said when a playable build goes live or when a
fix counts as live -->

- **Approach:** Stand up a playable web build on the first playable night and redeploy it on every merge. **Watch out
  for:** a playable link came late, so nobody could play the game where its players would. **Seen:** Deadnight,
  2026-11-01 (fix: deadnight's web build is hosted on Railway and CI redeploys it on each merge to `main`).
- **Approach:** After merging a fix for something the maintainer reported, watch `main`'s deploy, run the same probe
  against the live URL (for mouse look, the yaw probe), and only then report it as live. **Watch out for:** a fix
  counted as done when it merged: a flaky leak check (Deadnight #317) failed `main`'s CI three times, so the deploy job
  never ran and the site kept the old build. **Seen:** Deadnight #299, 2026-11-01 (fix: the report names the deployed
  commit and the probe run on the live URL).

## Browser probes {#browser-probes}

<!-- new section: the page's sections are each about one browser behaviour; nothing covered how the probes themselves
are written -->

- **Approach:** Pass the game's probe object through to a browser probe whole, or test that every published field
  reaches the page. **Watch out for:** the smoke read the probe through a list of named fields, so a new field (the
  camera yaw) read as missing and the first look check failed on a working build. **Seen:** Deadnight, 2026-11-01 (fix:
  running the check against a fixed and an unfixed build showed the fault was in the probe).
- **Approach:** Start every browser probe through one shared helper (`smoke.start_solo`), and run every probe's start-up
  in CI. **Watch out for:** each probe walked the menu with its own key sequence, so the menu rework (Deadnight #466)
  broke two silently (`pointer_lock.py` in #481's CI, `touch_look.py` live). **Seen:** Deadnight #466, 2026-11-02 (fix:
  deadnight #484 added the helper
  ([lesson](../../lessons/2026-11-02-each-browser-probe-walked-the-menu-its-own-way.md))).
