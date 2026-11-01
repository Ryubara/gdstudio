# UI controls

How custom-drawn controls behave in Godot 4.7, learned building GDStudio's UI addon (`gds_ui`).

| Topic | What we learned |
| --- | --- |
| Drawn controls | Extend the engine control for its behaviour (HSlider, Button), empty its styleboxes in a theme variation, and draw in `_draw` with springs. A script `_draw` on a Button runs after the native draw, so a fill drawn there paints over the text (found by capture, not in the docs): draw on a child control with `show_behind_parent`. |
| Tweens on a disabled or freed node | A node whose `process_mode` is `PROCESS_MODE_DISABLED` (a screen a router covers) never advances a tween created on it, so its animation never runs. A tween on a node that is freed is killed and its `finished` signal never fires, so an `await` on it waits forever. Create transition tweens on a node that stays enabled and outlives the screens (the router's stage), and check `is_instance_valid` after every await ([lesson](../lessons/2026-11-01-a-screen-freed-mid-transition-locked-the-router-for-good.md)). |
| Screen-reading shaders | `hint_screen_texture` makes the renderer copy the back buffer: +0.18 ms at 1080p and +12 MB for a full-screen grade ([Compatibility lighting](compat-lighting.md#full-screen-post-shader)), and it is the shader feature most likely to differ on a mobile or WebGL2 GPU. A screen transition does not need it: make it procedural (hash noise) over a colour the shader owns, close it over the old screen, swap behind it, then open. |
| Clear colour | Set `RenderingServer.set_default_clear_color` to the UI's background token. A fade or a screen swap that passes through "nothing" shows the engine's default grey, which no token owns. |
| A transition checklist | A pop is not a push played backwards: the screen that leaves must be on top, and only the transition may decide layering (never the stage's child order). For each transition capture the push **and** the pop, free the outgoing, the incoming and the popped screen mid-transition and check the router is idle, queue calls during it and check they run in order, and run it with reduced motion on. Deadnight's list: `game/addons/gds_ui/README.md` there. |
| Slider hit area | HSlider hit-tests with the grabber icon's width, so the theme's invisible grabber must be as wide as the drawn thumb. Check with a real InputEventMouseButton: a click at 60% of the travel gave 1.85 of 0.1 to 3.0. |
| Invisible textures | Never a PlaceholderTexture2D: it draws a magenta checker in game. Use a transparent ImageTexture. |
| Runtime UI scale | `Window.content_scale_factor` resizes CanvasLayer stages and anchored controls; with `canvas_items` stretch the visible area is the base size divided by the scale. Avoid autowrap Labels in rows: they inflate containers. |
| Resolution scale | `Viewport.scaling_3d_scale` only affects 3D. |
| Fitting text | A `Label` with `clip_text` or an ellipsis overrun has a minimum width of 0, so a container squeezes it to nothing: give it `custom_minimum_size.x`. Fit text from one measurement (size × room / width), since `get_string_size` shapes the string on every call. Test layouts with the longest values the game allows, and with a wide face: `FontVariation.variation_transform` makes a synthetic wide one, so CI needs no font file. |
| Baselines and label height | A Label is as tall as the font's line (about 1.4 times its size), not its capitals: size a box from that. `SIZE_SHRINK_END` aligns the bottoms of boxes, not baselines: put two sizes on one baseline with `baseline - font.get_ascent(size)` for each, or lift the smaller by the difference of the descents. |
| One-shot 3D portrait in a HUD | A `SubViewport` with `own_world_3d`, the model, a camera and lights, `render_target_update_mode = UPDATE_ONCE` two frames after the model enters (its idle clip must pose it), shown by a `TextureRect` on `viewport.get_texture()`; it costs nothing after that frame. |

Game write-ups: Deadnight's `docs/research/ui-foundation.md` and `docs/research/settings.md`.

## Touch controls

Touch controls press the game's existing input actions, so gameplay code does not fork. `Input.emulate_mouse_from_touch`
is off while they show, or every touch also clicks. Tests inject `InputEventScreenTouch` and `InputEventScreenDrag`
with `Input.parse_input_event`, in window pixels: multiply canvas positions by the viewport's `get_final_transform()`
first. On the web, set `viewport-fit=cover` and block page scroll, zoom and the long-press menu. Deadnight's design
and what its build showed: `docs/research/mobile-controls.md` there.

## Animating a container's children

- **Never read a container child's position in the frame it was shown.** A `Container` sorts its children in a
  deferred call that runs after `SceneTree.process_frame` is emitted, and input is handled before that signal, so
  `await process_frame` from a click resumes before the sort (unless a physics step flushed it first). A page never
  shown has its rows at (0, 0). Read positions two frames after the change, stop the previous tween of the same
  control, and `queue_sort()` the container when the tween ends.
- **Reproduce with real input**: `Input.parse_input_event`, not a direct call, and `Engine.physics_ticks_per_second = 1`
  so no physics step hides the race.
