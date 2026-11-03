---
areas: [godot, godot-ui, web]
---
# A menu's 3D stage looked pixelated on a 1440p screen: its viewport was the canvas size, not the window's pixels

2026-11-03

- **Saw:** the menu character had stair-stepped hair and hands (Deadnight #893). A real window at 2560 x 1440 showed the
  stage's `SubViewport` at 1920 x 1080; the phone page (1688 x 780 canvas) drew 2337 x 1080, more pixels than it has.
  Its own `msaa_3d` was 2x (the project setting does not reach a `SubViewport`).
- **Cause:** with `window/stretch/mode = canvas_items` a `Control` is sized in the 1920 x 1080 base canvas, and a
  `SubViewportContainer` with `stretch` sets its viewport to that size, then the window scales the picture. Setting
  `viewport.size` yourself is refused (a warning), and with `stretch` off the container grows to the viewport's size.
- **Fix:** a plain `Control` with a `SubViewport` child shown by a `TextureRect` on `get_texture()`; set the viewport to
  `size * get_viewport().get_final_transform().get_scale()` (capped at 1440 high), again on `resized` and on the root's
  `size_changed` (the same aspect changes the pixels without resizing the control). Check it in a real window at two
  resolutions, not headless (the root is 1920 x 1080 there): the capture probe prints the window, the control and the
  viewport sizes.
- **Docs:** [UI controls](../godot/ui-controls.md#3d-in-a-menu).
