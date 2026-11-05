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
| Pointer lock clips the real cursor | Headless Google Chrome (`channel="chrome"`) under pointer lock clipped the person's cursor to `(17, 68, 864, 541)` for the whole lock; Playwright's default headless shell did not clip. `gds quiet` frees it every 5 ms: 0 of 777 samples held ([lesson](../lessons/2026-11-02-a-headless-browser-under-pointer-lock-held-the-cursor.md)). |
| Pointer lock in headless Chromium | It works (`document.pointerLockElement` is the canvas after the click that starts the night), but on Linux, the CI runner, every synthetic `page.mouse.move` under lock arrives as a motion and then the opposite motion (+15 px, -15 px), which cancel. Windows does not do it. A smoke that must turn the view dispatches `new PointerEvent('pointermove', {movementX, bubbles: true})` on the canvas: Godot's web runtime listens for `pointermove` and reads `movementX/Y`. Check mouse look on the CI runner, not only on your own machine ([lesson](../lessons/2026-11-01-chromium-on-linux-cancelled-synthetic-mouse-moves-under-pointer-lock.md)). |
| Key taps | Godot reads input once per frame, so a tap shorter than a frame can be lost: hold keys for about 150 ms. |
| Focus after Back | After Back from a screen nothing has focus; the router spends the first arrow or accept key giving it focus. |
| Touch is a mouse too | Godot's web runtime turns every window `pointermove` into a mouse motion in device pixels, and a touch pointer fires `pointermove` as well, so each finger also turns a mouse-look camera (three times too far at a pixel ratio of 3). Stop touch `pointermove` in a capture-phase listener in `html/head_include` and prove phone input in a mobile-emulated Chrome with `Input.dispatchTouchEvent`, not with synthetic `InputEventScreenDrag` on desktop ([lesson](../lessons/2026-11-02-a-finger-is-a-mouse-motion-too-in-the-web-runtime.md)). |
| A new prompt in a flow | A prompt or wait added to a flow (a name asked at the first sign-in) changes every automated path through it: unit tests that call the screen and every web smoke that drives it start from a fresh profile and stop at the prompt, until the 5 minute test timeout or the smoke's wait. Search the screen, its route and its URL parameters in `tests/` and `tools/web_smoke/` and update each in the same change; a smoke answers the real prompt through a probe flag ([lesson](../lessons/2026-11-02-a-new-prompt-hung-every-test-and-smoke-that-passed-through-it.md)). |
| A ratio gate and a change that moves its denominator | The night-load gate is the night's load over the same run's load to the menu (limit 5.5x, Deadnight #873). A change that made the menu 7 s quicker (it stopped redrawing the 3D stage while the page came up) failed it three times in a row on nights that were in the usual range for the runner: the quotient rose, the night did not. Before reading a red ratio as a slower night, put both terms beside `main`'s runs and divide the night by something the change is unlikely to move (the idle menu's mean frame, `menu_frames.mean_ms`, tracked the night: 0.4 to 0.8 s per ms on `main`, 0.4 to 0.9 on the failing runs) ([lesson](../lessons/2026-11-04-a-faster-menu-failed-a-gate-that-divides-by-the-menu-load.md)). |
| A script's answer is an int | `JavaScriptBridge.eval` hands a script's `true` back as the integer 1. `answer == true` is then an invalid operation, which a release build stops the function at without a word (no error in the console); a value meant to be cached was asked of the page again at every read (about 5 evals a second, Deadnight #983). Read an answer with `bool(answer)` or `int(answer)` ([lesson](../lessons/2026-11-04-a-cached-answer-was-asked-again-because-eval-returns-an-int.md)). |
| A frame time on a software renderer, compared | Frame times in SwiftShader moved by half or more (20 to 31 ms for one build) with whatever else the machine ran, so a before and after of two builds says nothing until it is in turns, many times. Count instead what the engine asks of WebGL in each frame (wrap `WebGL2RenderingContext.prototype.drawArrays`, `drawElements`, `clear`, `blitFramebuffer`, `bindFramebuffer`, `texImage2D`... for the seconds measured only and put them back: a wrapper on the whole night slows what a time gate reads): the counts do not move with the machine, so equal counts mean the two builds do the same work. The GPU process's CPU seconds (`SystemInfo.getProcessInfo` on a browser-level CDP session) are SwiftShader's threads spinning: 207 ms a frame whether the frame took 20 ms on 16 cores or 30 ms on 2, so it shows "the same", not "how much". To test a slower machine pin the whole run (`Start-Process -PassThru`, then `.ProcessorAffinity`: the browser inherits it) rather than `Emulation.setCPUThrottlingRate`, which slows only the page's main thread. Deadnight `tools/web_smoke/menu_idle.py`, `docs/research/web-export.md` "The idle menu after #920". |
| Hosted runners are several CPU models | A CI label (`ubuntu-24.04`) is a pool: the same web build's idle menu frame in SwiftShader was 60 ms on an AMD EPYC 9V45, 73 on an Intel Xeon 6975P-C, 80 on a 9V74, 98 to 100 on an EPYC 7763 and a Xeon 8573C and 119 to 121 on a Xeon 8370C, so a run's frame time says little until its machine is written beside it (the smoke records `machine`: CPU model, usable CPUs, load). To tell a change from the runners, run the builds before and after in turns on the same runners: a throwaway workflow (a push trigger on the branch, `paths` on itself) that downloads each commit's `web-build` artifact by id and runs the measure in a matrix of 20 to 24 jobs with `lscpu` printed; the same build then reads 60 to 120 ms between runners and the same on one, and a change shows within a runner (a 1 % step was seen in 15 of 20). To read many old runs, fetch `smoke/result.json` only (HTTP range requests on the artifact's signed address: 70 KB instead of 34 MB a run; Deadnight `tools/web_smoke/smoke_history.py`) ([lesson](../lessons/2026-11-04-ci-runners-are-six-cpu-models-and-the-smoke-recorded-none.md)). |
| A saved file in a browser run | A web export keeps `user://` in the page's IndexedDB: database `/userfs`, object store `FILE_DATA`, one record a file under `/userfs/godot/app_userdata/<project name>/<file>`, its bytes in `contents` (`new TextDecoder().decode(record.contents)`). A run proves that a file survives a reload by reading it there with `page.evaluate` (list the store's keys when the path is wrong: the project name is part of it), reloading the same context (a new context has empty storage) and reading what the game found again through `window.deadnight`; the write is mirrored from the page a moment after the file is closed, so poll for it. Two traps met on the way: Deadnight's `smoke.probe` returns only the keys the older probes read, so a new probe key is read with `Object.assign({}, window.deadnight)` (as `lobby.py` does), and a lobby the first visit made is still held by the backend after the reload (409 `already_in_lobby`: leave it first). Deadnight `tools/web_smoke/guest_account.py` (#1080). |
| A last request when the page closes | A `fetch` or beacon sent from `pagehide` is proved by closing a real tab (`page.close()`) in Chromium, Firefox and WebKit, against a deployed backend or a proxy that holds each request 150 ms. `sendBeacon(url, string)` (a `text/plain` request with the token in the body) arrived 5 of 5 in all three at one round trip; a `Blob` body was never sent by Firefox on a close; an `application/json` body (a preflight) by none; a `fetch` with `keepalive` and an `Authorization` header also arrived, in two round trips. Send it only for `pagehide` with `persisted` false: a phone's app switch fires `visibilitychange` and no unload, and the back-forward cache fires `pagehide` with `persisted` true. To emulate a tab that is away, hold its requests (`route.fallback()` later), never abort them. Deadnight `tools/web_smoke/page_closing_transport.py` and `page_closing.py` (#1188) ([lesson](../lessons/2026-11-05-a-beacon-with-a-blob-body-was-never-sent-by-firefox-on-close.md), [lesson](../lessons/2026-11-05-a-quiet-tab-emulated-by-refusing-requests-measured-the-refusal.md)). |
| Which GPU | The browser masks the adapter from Godot; read `UNMASKED_RENDERER_WEBGL` (`WEBGL_debug_renderer_info`) through `JavaScriptBridge` to spot SwiftShader and fall back to a cheaper scene ([lesson](../lessons/2026-11-02-a-browser-masks-the-gpu-from-godot.md)). |

## Pointer lock and Esc: design it in from the first playable night

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

Lesson: [Esc in the browser freed the cursor but did not pause the game](../lessons/2026-11-02-esc-in-the-browser-freed-the-cursor-but-did-not-pause.md).

## Discord Activity: the proxy and the iframe

A Discord Activity is the web build in an iframe on `<id>.discordsays.com`, reaching outside hosts only through its
URL mappings. A build that works in a browser tab can fail there in three silent ways (Deadnight #469, #475, #479):

- **The mapping keeps its prefix.** `/api` mapped to the backend forwards `/api/auth/guest` unchanged: serve the routes
  with and without the prefix ([lesson](../lessons/2026-11-02-discord-activity-proxy-keeps-the-mapping-prefix.md)).
- **Answers come gzipped and are decoded twice.** The browser decodes them but keeps `Content-Encoding: gzip`, and
  Godot's `HTTPRequest` decodes again and fails with status 0, while the server logged 200. Set
  `HTTPRequest.accept_gzip = false` in the web build, and trade an OAuth code once
  ([lesson](../lessons/2026-11-02-a-godot-web-client-decoded-gzip-twice-behind-a-proxy.md)).
- **No focus, no gamepad.** The iframe starts without the focus, and Chromium lists no pad to it until the player
  clicks in it and presses something; Godot swallows the error. Focus the window and canvas on the first pointer or
  key event, and tell the player on screen to click once
  ([lesson](../lessons/2026-11-02-an-activity-iframe-lists-no-gamepad-until-a-click.md)).

An agent cannot open an Activity, so stand one in before asking the maintainer to try: a local HTTPS host for
`<id>.discordsays.com` (Chrome `--host-resolver-rules`) that keeps the prefix and gzips its answers, an iframe of
another origin, a parent that keeps the focus, a virtual pad (Deadnight `tools/web_smoke/activity.py`, under
`gds quiet`). Walk sign-in, lobby, ticket and WebSocket through it, test focus in a headed browser (headless Chromium
reports the focus as held), and read the backend log of the maintainer's first try. Test runs with fresh instance ids
hold game-server slots until they are swept, so use few per run. A CI deploy of `main` replaces a hotfix deployed from
a branch: check `railway deployment list --service web` before the maintainer retries.

## Discord Activity: copy and paste in the frame

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

Lesson: [Copy and paste did nothing in the Discord Activity](../lessons/2026-11-02-an-activity-frame-could-not-copy-or-paste.md).
Lesson: [The first Ctrl+V in a browser tab pasted nothing](../lessons/2026-11-02-the-first-ctrl-v-in-a-browser-tab-pasted-nothing.md).
Lesson: [Share in Discord said "Pick who to send it to" and Discord opened nothing](../lessons/2026-11-02-a-share-button-said-pick-who-to-send-it-to-whatever-discord-answered.md).
Lesson: [A harness that faked the host's answers passed, and the real host refused with 4006](../lessons/2026-11-03-a-harness-that-faked-the-hosts-answers-passed-a-refusal-it-never-met.md).

## A phone's keyboard in the web build

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
