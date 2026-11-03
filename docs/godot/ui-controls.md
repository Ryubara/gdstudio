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

## A control that draws outside its rect

A scale, a shadow or a focus ring is drawn outside the control's rectangle, and the rectangle is all a container knows:
nothing reserves room for it, and a `ScrollContainer` (always) or any control with `clip_contents` cuts it off at its
own edge. A hover that scales a button 3.5 percent loses 14 units at each side of a full-width 800-unit button. Do not
fix it screen by screen:

- **The control guards itself.** Before it grows it measures the free room to its nearest clipping ancestor
  (`clip.get_global_transform().affine_inverse() * parent.get_global_transform() * Rect2(position, size)`, so the
  scales of the ancestors count) and grows by that much per axis at most.
- **The theme leaves room.** `ScrollContainer` has a `panel` stylebox whose content margins move the content in; an
  empty one with margins on all four sides gives every scroll area room without code in the screens. The sides need
  `hover_room` (the growth of a wide button and its ring); above and below only the ring and the growth of a row of
  its height (`scroll_room`, 12 units). The margin is empty space at the ends of the content only, since the area
  still clips at its own edge. A screen that sizes its scroll area from the content adds the margin
  (`UIScroll.margins(scroll)`), and one that asks how far it scrolls reads the bar's `page` (the inner height), never
  `scroll.size.y`. Leaving the vertical margin out "because screens compute the height" kept the ring cut at the first
  and last row (Deadnight #644): fix the arithmetic of the two screens, not the theme.
- **The area's own follow stops at the control's edge.** `follow_focus` scrolls the control's rectangle into view, not
  its ring, so a row reached with the keyboard sits flush and its ring is cut even with the margin. One listener
  (`gui_focus_changed`, only when a key or a pad moved the focus, deferred past the area's own follow) scrolls the rest
  of the way; a hovering mouse must not move the area under itself.
- **Test it as a sweep.** Hover every button of every screen at every canvas, scroll the area to its top, end and middle
  (a button is also clipped at the content's ends), and compare the grown rect with the clipper's rectangle. Add a case
  that the buttons still grow: a guard that shrinks them to nothing passes the first test for the wrong reason.
  `Control.size_flags` `EXPAND_FILL` rows are the usual victims. Measure the ring (`focus_gap + focus_border`) on
  all four sides, not the sides alone: a sweep that grows the rect one way only passes the other.
  And walk the focus onto every button as a key does, not only scroll to the top, end and middle: the follow stops flush
  at the edge.

Deadnight #628 and #644: `game/tests/ui/test_hover_room.gd`.

## A picker of cards in a form row

A choice that needs a picture and a few facts (Deadnight's map picker, `MapPicker` and `MapCard`) is a column of
focusable `Button` cards inside a `UIRow`'s control column, not a bigger `UIOptionSelector`.

- **Draw the card the way the menu draws its tickets** (`MenuLook.draw_ticket`, the amber outline for the focus or the
  pointer, hover moving the focus) so it reads as part of the menu and nothing new has to be themed. The chosen card
  is marked in a second colour (red outline and a word) so focus and choice never look the same.
- **A card that cannot be chosen yet still takes the focus.** A keyboard can read it; its press says `blocked` and
  changes nothing. A read-only copy (a guest's lobby) sets `focus_mode` to none and `mouse_filter` to ignore.
- **Budget the phone's height before the desktop's.** A phone held sideways has 540 units, and a form that already
  fills them takes no new row: a `GridContainer` that goes from one column to two, tighter gaps and a card without a
  picture kept the Play screen inside the canvas. After the columns change, set the focus neighbours again.
  Headless tests cannot see this overflow (text measures as nothing): run the capture tour at 844 by 390
  ([lesson](../lessons/2026-11-03-a-new-row-pushed-a-form-off-a-phone-held-sideways.md)).
- **Test every input the card takes:** arrow keys and Enter (`get_viewport().push_input` with `InputEventKey`), the
  d-pad and A (`InputEventJoypadButton`), and a tap (`InputEventScreenTouch` plus the emulated mouse button), on the
  card chosen and on the card that is locked.

## Touch controls

Touch controls press the game's existing input actions, so gameplay code does not fork. `Input.emulate_mouse_from_touch`
is off while they show, or every touch also clicks. Tests inject `InputEventScreenTouch` and `InputEventScreenDrag`
with `Input.parse_input_event`, in window pixels: multiply canvas positions by the viewport's `get_final_transform()`
first. On the web, set `viewport-fit=cover` and block page scroll, zoom and the long-press menu. Deadnight's design
and what its build showed: `docs/research/mobile-controls.md` there.

A new HUD part must be tested against the touch buttons too (a list of kept cards in the layout test) and captured on a
phone: the right thumb's corner is full, and rectangle tests between HUD parts do not see it
([lesson](../lessons/2026-11-03-a-new-hud-card-sat-under-the-touch-buttons.md)). A HUD part's `refresh` must not need the
tree: `global_transform` of a node not yet inside it is an error and an identity
([lesson](../lessons/2026-11-03-a-hud-part-built-a-model-bounds-before-it-was-in-the-tree.md)).

## Animating a container's children

- **Never read a container child's position in the frame it was shown.** A `Container` sorts its children in a
  deferred call that runs after `SceneTree.process_frame` is emitted, and input is handled before that signal, so
  `await process_frame` from a click resumes before the sort (unless a physics step flushed it first). A page never
  shown has its rows at (0, 0). Read positions two frames after the change, stop the previous tween of the same
  control, and `queue_sort()` the container when the tween ends.
- **Reproduce with real input**: `Input.parse_input_event`, not a direct call, and `Engine.physics_ticks_per_second = 1`
  so no physics step hides the race.

## Menus under test

- **Transparent is not unreachable.** A control at `modulate.a = 0` is still focusable and clickable. While a menu's
  items are hidden or entering, set `mouse_filter` to ignore and `focus_mode` to none, keep the old values, and give
  them back when the entrance ends
  ([lesson](../lessons/2026-11-01-a-hidden-menu-item-was-still-focusable-and-clickable.md)).
- **Headless mouse in GdUnit4.** The window is 64 x 64 pixels, so mouse events sent with `Input.parse_input_event` land
  outside it. Send them with `get_viewport().push_input(event, true)`; keys still go through
  `Input.parse_input_event` ([lesson](../lessons/2026-11-01-a-headless-gdunit4-window-is-64-pixels-wide.md)).
- **Captures of a tour scene.** Await each step's note before the next: a coroutine called without `await` carries on
  and the PNG is taken a few frames late.

- **Parsed input is buffered.** After `Input.parse_input_event`, call `Input.flush_buffered_events()` and wait two
  frames before reading action state ([lesson](../lessons/2026-11-02-a-parsed-input-event-is-buffered.md)).
- **Counts sit in containers beside their text**, never at a hand-measured offset: the offset breaks with the next
  font, scale or translation (Deadnight #466).
- **A centred panel is measured in its tallest state at 720 high.** A `CenterContainer` panel grows with its content
  and runs off a 720-high frame (a Discord Activity, a laptop) when every optional line shows (the Together invite
  panel, the lobby): put side-by-side buttons in an `HBoxContainer`, ellipsise one-line text, wrap the content in a
  `ScrollContainer` capped at the viewport height minus the panel's margin with `follow_focus = true`, and call
  `ensure_control_visible` two frames after showing a field the player must reach. Test the panel's size in a
  `SubViewport` of 1280 x 720 with every optional line shown
  ([lesson](../lessons/2026-11-02-a-panel-grew-past-a-720-high-frame.md)).

## A menu over a live game

- **Do not push a screen over a game that must keep running.** `UIRouter` disables the screen it covers
  (`process_mode = DISABLED`), which is right for a solo night and wrong for a multiplayer one (the link is no longer
  read). Hold the sub-screen (settings) as a child of the menu instead, with a `closed` signal for its Back, and take
  Esc, B and Start in the owner: the child's own `ui_cancel` must go back one step, not resume
  ([lesson](../lessons/2026-11-02-a-menu-pushed-on-the-router-froze-the-night-behind-it.md)).
- **Solo stops the simulation, online it does not**: only the player's controls go off, and the card says so
  ("Menu: the night goes on around you", not "Paused").
- **In a test, wait for the router only while it is busy** (`if UIRouter.busy: await UIRouter.idle`): the signal is not
  replayed to a waiter that comes after it.
