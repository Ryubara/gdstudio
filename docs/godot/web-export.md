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
