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
