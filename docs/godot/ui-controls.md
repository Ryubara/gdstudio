# UI controls

How custom-drawn controls behave in Godot 4.7, learned building GDStudio's UI addon (`gds_ui`).

| Topic | What we learned |
| --- | --- |
| Drawn controls | Extend the engine control for its behaviour (HSlider, Button), empty its styleboxes in a theme variation, and draw in `_draw` with springs. A script `_draw` on a Button runs after the native draw: put fills behind text deliberately. |
| Slider hit area | HSlider hit-tests with the grabber icon's width, so the theme's invisible grabber must be as wide as the drawn thumb. Check with a real InputEventMouseButton: a click at 60% of the travel gave 1.85 of 0.1 to 3.0. |
| Invisible textures | Never a PlaceholderTexture2D: it draws a magenta checker in game. Use a transparent ImageTexture. |
| Runtime UI scale | `Window.content_scale_factor` resizes CanvasLayer stages and anchored controls; with `canvas_items` stretch the visible area is the base size divided by the scale. Avoid autowrap Labels in rows: they inflate containers. |
| Resolution scale | `Viewport.scaling_3d_scale` only affects 3D. |

Game write-ups: Deadnight's `docs/research/ui-foundation.md` and `docs/research/settings.md`.
