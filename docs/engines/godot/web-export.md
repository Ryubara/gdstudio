# Web export: what the browser build does differently

What running the web build of a game in a browser taught us: pointer lock and Esc, the Discord Activity, a phone's
page, keyboard and touch, and what only the export shows. How to drive the build in a headless browser, and gate on
what it measures, is on [Browser probes](web-probes.md); the setup is Deadnight's web smoke
(`tools/web_smoke/smoke.py` there, Playwright driving the export), and the game write-up is its
`docs/research/web-export.md`.

**Run every local browser probe through `gds quiet`** (Windows), as [Browser probes](web-probes.md#running) says: under
pointer lock headless Chrome confines the real cursor of the person at the machine until Esc.

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

- **Approach:** In a web game with mouse look, pause on the loss of pointer lock (or focus), not on the key; ignore look
  and fire while unlocked, re-lock from a button press, and have the web smoke release the lock and check the pause
  screen. **Watch out for:** in a browser the first Esc only exits pointer lock and never reaches the game, so the
  game's `pause` key never came and mouse look and fire kept running with a free cursor. **Seen:** Deadnight, 2026-11-02
  (fix: the pause follows the lock, as above; it belongs in a web game's first design); gdstudio #881, 2026-11-10 (the
  template's `ScreenHost` does it for every game made from 3D Third Person, and `tools/web_smoke/pause_smoke.py`
releases
  the lock in Chromium and reads the menu up).

## Discord Activity: the proxy and the iframe {#discord-activity-the-proxy-and-the-iframe}

A Discord Activity is the web build in an iframe on `<id>.discordsays.com`, reaching outside hosts only through its
URL mappings. A build that works in a browser tab can fail there in three silent ways (Deadnight #469, #475, #479):

- **The mapping keeps its prefix.** `/api` mapped to the backend forwards `/api/auth/guest` unchanged: serve the routes
  with and without the prefix.
- **Answers come gzipped and are decoded twice.** The browser decodes them but keeps `Content-Encoding: gzip`, and
  Godot's `HTTPRequest` decodes again and fails with status 0, while the server logged 200. Set
  `HTTPRequest.accept_gzip = false` in the web build, and trade an OAuth code once.
- **No focus, no gamepad.** The iframe starts without the focus, and Chromium lists no pad to it until the player
  clicks in it and presses something; Godot swallows the error. Focus the window and canvas on the first pointer or
  key event, and tell the player on screen to click once.

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
  2026-11-02 (fix: deadnight #482).
- **Approach:** Say something happened only after the host says so; a harness that fakes a host answers as the host can
  (refused, unauthenticated, missing scope, an error object, silence) and runs the real SDK handshake, and a platform
  fix is proven in the real client before its issue closes. **Watch out for:** the share button claimed Discord's picker
  opened whatever Discord answered, while the stub always said yes; the first fix passed, but the bridge never called
  `authenticate`, so Discord refused `shareLink` with RPC 4006. **Seen:** Deadnight #627, 2026-11-02; Deadnight #627,
  2026-11-03 (fix: deadnight #649, then the handshake).

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

- **Approach:** Run any feature that moves text in or out of the game (codes, names, links) in the Activity iframe
  harness with a denying policy, and show a "done" message only after the platform confirms the result. **Watch out
  for:** the clipboard is a permission of the host: a cross-origin iframe has no clipboard API by default and Godot's
  web runtime cancels every canvas `keydown`, so Ctrl+V made no `paste` event, and the screen said "Code copied."
  without checking. **Seen:** Deadnight #516, 2026-11-02 (fix: the paste and copy layer of this section, Deadnight #533).

## Discord Activity: the same game as the website {#activity-same-game}

<!-- new section: the Activity sections cover the proxy and the frame; none says the Activity behaves as the
website does -->

- **Approach:** Give the Discord Activity the website's flow at every step: it opens on the main menu, Play together
  shows the code field and the create button, and nothing is made until the player presses; search every platform branch
  (`instance_id`, `in_discord()`) and remove what a press does there and not on the website, unless the maintainer
  asked. **Watch out for:** a launch went straight to Play together without asking; the fix moved the first screen and
  kept the shortcut behind it, a lobby per instance id, so a second player got a lobby of their own. **Seen:**
  Deadnight #495, 2026-11-02; Deadnight #1178, 2026-11-05 (fix: a platform identity is never a room key; a test
  fails on any lobby request from the Activity's screen).

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
  font and keypad work of this section).

## A phone page's size: the canvas is not the page {#a-phone-pages-size-the-canvas-is-not-the-page}

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
- **One helper for the page's height.** In 3D Third Person, `Hud.css_height()` gives the page height in CSS px (the
  canvas element's box on the web, the window over the pixel ratio elsewhere); a part that sizes itself by the page asks
  it rather than doing its own sums ([The template HUD](ui-layout.md#template-hud), gdstudio #880).

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

## A phone's touch, taps and fit {#phone-touch-and-fit}

<!-- new section: the keyboard and page-size sections say what a phone page is; nothing held how a finger and a phone's
canvas break what passed on a desktop window -->

- **Approach:** Stop touch `pointermove` in a capture-phase `window` listener in the export's `html/head_include`
  (`stopImmediatePropagation()` for `pointerType === 'touch'`), ignore in the game a mouse motion that is not the touch
  layer's own while a finger was the last input, and prove phone input in a mobile-emulated Chrome with
  `Input.dispatchTouchEvent`. **Watch out for:** Godot's web runtime turns every window `pointermove` into a mouse
  motion in device pixels, and a touch pointer fires `pointermove` too, so each finger also turned a mouse-look camera,
  three times too far at a pixel ratio of 3; synthetic `InputEventScreenDrag` in the desktop runner never takes that
  path and `Input.emulate_mouse_from_touch = false` does not touch it. **Seen:** Deadnight #470, 2026-11-02 (fix:
  the listener and the game's guard, Deadnight #480).
- **Approach:** When a layout is off screen at one size, read the canvas the game reports and ask who set the scale
  before moving a button: a screen that is not the menu sets the scale it is made for when it starts, and the menu
  re-applies its factor when it shows again, never while hidden. **Watch out for:** the menu doubles the units on a phone
  (`content_scale_factor` 2, a canvas 540 units high) and gives them back only when it leaves the tree, but a night is
  pushed over the menu, which stays; the HUD and touch layer made for 1080 ran on half a canvas and a button placed 690
  up sat at page y -108. The first fix moved one button. **Seen:** Deadnight #588, 2026-11-02 (fix: `NightScreen` puts
  the player's own UI scale on the window; a test pushes a night over a phone menu, a probe checks every button's
  circle against an 844 by 390 page).
- **Approach:** Say which pixel a phone size or a tap target is in (units, window pixels, CSS pixels): a size a finger
  meets is in CSS pixels, so the least size is the CSS minimum times the page's ratio over the pixels to a unit, the
  switch is "a finger is the pointer" (`TouchMode.wanted`) and not the window's size, and one case runs at the real
  page's size (1688 by 780, ratio 2). **Watch out for:** a headless window of 844 by 390 has a ratio of 1, so tests and
  switch agreed with themselves, while a real phone page of that CSS size is a 1688 by 780 window, which a short-side
  test calls "not a phone", where 44 window pixels are 22 CSS pixels. **Seen:** Deadnight #1192, 2026-11-05 (fix:
  `night_taps.py` reads the exported page's buttons, 44.1 CSS px, and presses one with a real touch at its edge).
- **Approach:** Check a control meant to be on screen beside another on the real phone page (844 x 390 CSS px, ratios 2
  and 3), by its position in the viewport and by a tap, not by "the row is visible" in a fixture; scroll the test's
  area to the end as well when a screen scrolls to a focused control, and let a title keep its whole text with the
  choices two to a row. **Watch out for:** the lobby scrolls to Start (`follow_focus`); a suite stopped with Start at
  the bottom, while on the page the copy buttons under Start pushed the scroll further and the Private switch sat half
  out of the top; a trimming `Label` asks a container for no width, so a column's least width won and a title read
  "Break between ro...". **Seen:** Deadnight #1186, 2026-11-05 (fix: `LobbyPrivateSwitch.reveal` scrolls back; a
  `test_phone_fold` asserts every control lies in the scroll's view on each real page).

## What only the export shows {#export-only}

<!-- new section: the sections above are each one browser behaviour; nothing held the faults that show only in the
exported page, not in the editor, a headless import or a desktop run -->

What the exported page itself does before the engine boots, the WebGL context it makes with the attributes Godot asks
for and the extensions Emscripten enables, and the shader list it links while the engine downloads, is on
[First-use hitches: the page starts it](first-use-hitches.md#prelink-page) (gdstudio #1214).

- **Approach:** To ship a smaller copy of an imported resource (an animation library with fewer clips), customize it
  in an `EditorExportPlugin`: `_begin_customize_resources` returns true, `_customize_resource` returns the copy for
  that resource and null for every other, and `_get_customization_configuration_hash` hashes whatever decides the
  copy; read the pack afterwards (`load_resource_pack(pck, true)`, then load with `CACHE_MODE_IGNORE`).
  **Watch out for:** the export caches customized files under that hash, so a hash without the clip list ships the
  old copy after the list changes; and a GdUnit run cannot make an `EditorExportPlugin` ("can only be instantiated
  by editor"): put the logic in static functions. **Seen:** kit #1366, 2026-11-13 (`ClipExport`: 4.7.2 hands the
  imported library to `_customize_resource`; 86 clips to 16).
- **Approach:** Grep for `class_name <Name>` before choosing one, and export the web build before calling a new script
  class done. **Watch out for:** two scripts that say `class_name NeonSign` print `Parse Error: Class "NeonSign" hides
  a global script class` and the script fails to load only in the web export; the editor, a headless import and the
  captures showed nothing. **Seen:** Deadnight, 2026-11-01 (fix: the new script was renamed `LotNeonSign`).
- **Approach:** Write shader math that GLSL ES 3.0 defines: `d * d` for `pow(x, 2.0)`, `smoothstep` edges in order
  (clamp the width with `max`), one shared sine-free hash in a `.gdshaderinc` included with `#include`; look at it in a
  real browser export. **Watch out for:** desktop drivers return something sensible for `pow(negative, 2.0)`, reversed
  `smoothstep` edges and `sin` hashes, while WebGL2 drivers may give NaN or stripes, so nothing showed on the
  developer's machine. **Seen:** Deadnight, 2026-11-01 (fix: found in a review; the shaders share the hash).
- **Approach:** Keep `*.json` in the export's include filter as insurance, and prove a plain-file dependency (`.cfg`,
  `.txt`, `.csv`) by opening the screen that reads it in the browser export. **Watch out for:** old docs said a web
  export loses a `.json` file without the filter; in Godot 4.7.2 an empty filter gives the identical `.pck` (same
  md5), because 4.4 and later treat `.json` as a resource type, but other plain files still need it. **Seen:**
  Deadnight, 2026-11-01 (fix: the claim was measured, not assumed).
- **Approach:** Put no backslash in an export option such as `html/head_include`: use `String.fromCharCode(10)` for a
  newline and single quotes only, grep the changed line for `\` and `"` before exporting, then read the script's
  output on the exported page. **Watch out for:** Godot reads an option value as a quoted string with escapes, so
  `.join('\n')` became a real line break inside a JS string literal: a syntax error that kills the whole script, while
  the page looks fine without it. **Seen:** Deadnight, 2026-11-05 (fix: `phone_view.py` reads the readout on the
  exported page).
- **Approach:** Read a `JavaScriptBridge.eval` answer with `bool(answer)` (and `answer != null`) or `int(answer)`,
  never `answer == true`; when a cache on the web does not hold, log after each statement of the filling code (a
  second `eval` of `console.log`) before guessing at the engine. **Watch out for:** the web runtime hands a script's
  `true` back as the integer 1, `1 == true` is an invalid operation, and a release build ends the function there
  without a word: a value cached once was asked of the page about 5 times a second, and "in a frame" was never
  reported in a Discord Activity. **Seen:** Deadnight #983, 2026-11-04 (fix: a static function turns the answer into
  a bool; a test feeds it 1, true, 0, false and null).
- **Approach:** To fall back to a cheaper scene on software rendering, read `UNMASKED_RENDERER_WEBGL`
  (`WEBGL_debug_renderer_info`) through `JavaScriptBridge` and match SwiftShader or another software renderer.
  **Watch out for:** browsers mask the GPU adapter from the page, and Godot's web build sees only the masked string,
  which does not name the renderer. **Seen:** Deadnight #466, 2026-11-02 (fix: the live 3D menu drops to a still stage
  on a software renderer).

## Skinned meshes on Direct3D 11: the buffer hint {#skin-buffer-hint}

<!-- new section: the sections above are about the page, input and shaders; nothing said what the browser's GL
backend does with the buffers the engine skins meshes into, which set a skinned body's draw cost (gdstudio #1260) -->

The Compatibility renderer skins a mesh on the GPU, by transform feedback, into a vertex buffer of each skinned
`MeshInstance3D`'s own, made empty with `GL_DYNAMIC_DRAW` (Godot's `drivers/gles3/storage/mesh_storage.cpp`,
`_mesh_instance_add_surface`). Chrome, Edge and Firefox on Windows run WebGL on ANGLE's Direct3D 11 backend, which
treats the hint as a promise ([ANGLE's `Buffer11::supportsDirectBinding`, `BufferD3D::promoteStaticUsage`](https://chromium.googlesource.com/angle/angle/+/refs/heads/main/src/libANGLE/renderer/d3d/BufferD3D.cpp)):

- A buffer made with `DYNAMIC_DRAW` is never bound to a draw. Its attributes are copied into a streaming buffer at
  every draw, from a copy in system memory, which for a buffer the GPU just wrote is a read back from the GPU.
- After 3 times the buffer's size has been copied with no write in between, ANGLE turns it into a static buffer for
  good and binds it directly. Every write (the skinning, each frame) resets the count, so a body that animates every
  frame never gets there; a body drawn for 3 frames or more with its pose held (frozen, or its animation paused) does,
  at once, and stays fast.

So a skinned body's cost depends on its past. In `tools/bench/mannequin_draw_bench.tscn` (3D Third Person, an RTX 5080,
16 walking bodies) a body cost 0.09 to 0.15 ms a frame with its buffer streamed and 0.05 to 0.09 bound, at 10 to 80 %
processor load; under heavier load the streamed one read 0.2 to 0.45 ms, at random per buffer and page, since which
buffers had once been held still differed from page to page
([the bench's numbers](../../tools/blender/prototype-mannequins.md#browser-cost)). The Quaternius male of the same
bench read 0.08 to 0.12 bound and 0.09 to 0.13 streamed, with worst rounds to 0.32.

`SkinBuffers` (`addons/gds_game/skin_buffers/`) fixes it from the page: with the `gds_game` editor plugin on, a web
export writes a script first in `index.html`'s head that makes an array buffer created empty with `DYNAMIC_DRAW` with
`STATIC_DRAW` instead, on a Direct3D renderer only. The engine makes only its skinned and blend shape outputs and one
small 2D buffer that way; the hint is a hint in GL, so the engine writes the buffer as before and ANGLE binds it.
`window.gdsSkinBuffers` counts the buffers changed and `window.gdsSkinBuffersOff = true`, set before the engine boots,
turns it off for a measurement (`mannequin_draw_bench.py --dynamic-skin`).

- **Approach:** When a browser cost is bimodal (a cell reads its normal cost or two to four times it, and stays so for
  whole rounds or the whole page), keep each round's numbers in order and look for a warm-up that flips once, then read
  the GL backend's source for a usage counter (ANGLE's `D3DBufferUsage`, `mUnmodifiedDataUse`). **Watch out for:** the
  slow pages were read as noise and then as the machine's load; a frozen-body cell earlier in the bench's round had
  held every near body still, promoting those buffers, so only the far levels' own buffers (and the bench's
  rebuilt bodies, never frozen) stayed streamed, and a page with no frozen cell read everything slower and looked like
  a busy machine. **Seen:** gdstudio #1260, 2026-11-11 (fix: `SkinBuffers`; ten page loads of ten at 0.05 to 0.09 ms a
  body at every level).

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

The rest of writing and gating probes is on [Browser probes](web-probes.md).

- **Approach:** Pass the game's probe object through to a browser probe whole, or test that every published field
  reaches the page. **Watch out for:** the smoke read the probe through a list of named fields, so a new field (the
  camera yaw) read as missing and the first look check failed on a working build. **Seen:** Deadnight, 2026-11-01 (fix:
  running the check against a fixed and an unfixed build showed the fault was in the probe).
- **Approach:** Start every browser probe through one shared helper (`smoke.start_solo`), and run every probe's start-up
  in CI. **Watch out for:** each probe walked the menu with its own key sequence, so the menu rework (Deadnight #466)
  broke two silently (`pointer_lock.py` in #481's CI, `touch_look.py` live). **Seen:** Deadnight #466, 2026-11-02 (fix:
  deadnight #484 added the helper).
