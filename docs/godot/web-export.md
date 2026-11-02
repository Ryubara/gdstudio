# Web export: testing the browser build

What running the web build of a game in a headless browser taught us. The setup is Deadnight's web smoke
(`tools/web_smoke/smoke.py` there, Playwright driving the export); the game write-up is its
`docs/research/web-export.md`.

| Topic | What we learned |
| --- | --- |
| Pointer lock in headless Chromium | It works (`document.pointerLockElement` is the canvas after the click that starts the night), but on Linux, the CI runner, every synthetic `page.mouse.move` under lock arrives as a motion and then the opposite motion (+15 px, -15 px), which cancel. Windows does not do it. A smoke that must turn the view dispatches `new PointerEvent('pointermove', {movementX, bubbles: true})` on the canvas: Godot's web runtime listens for `pointermove` and reads `movementX/Y`. Check mouse look on the CI runner, not only on your own machine ([lesson](../lessons/2026-11-01-chromium-on-linux-cancelled-synthetic-mouse-moves-under-pointer-lock.md)). |
| Key taps | Godot reads input once per frame, so a tap shorter than a frame can be lost: hold keys for about 150 ms. |
| Focus after Back | After Back from a screen nothing has focus; the router spends the first arrow or accept key giving it focus. |
