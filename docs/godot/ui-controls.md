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
| An overlay in a padded container | A `PanelContainer` (any container with content margins) lays out every child inside the margins, an overlay such as a border included, so padding for the words shrinks the border with them. Give the overlay its own room: draw it outside its rectangle by the margin (a `grow` on the control; drawing outside the rect is allowed), and take the room from the content, not from the container, so the row keeps its width ([lesson](../lessons/2026-11-05-a-border-over-a-plate-shrank-with-its-padded-container.md)). |
| Invisible textures | Never a PlaceholderTexture2D: it draws a magenta checker in game. Use a transparent ImageTexture. |
| Runtime UI scale | `Window.content_scale_factor` resizes CanvasLayer stages and anchored controls; with `canvas_items` stretch the visible area is the base size divided by the scale. Avoid autowrap Labels in rows: they inflate containers. A phone capture needs the game's own factor (`MenuScale.factor(window.size, 1.0)`), or it shows the design canvas shrunk, not the phone's layout ([lesson](../lessons/2026-11-05-a-phone-capture-without-the-phone-scale-showed-the-wrong-layout.md)). **On a web page the window is the canvas in device pixels** (the ratio is capped at 2: an 844 x 390 phone page is 1688 x 780), so "a phone" is the page's short side in CSS pixels, not the window's; a test or capture names a page, never a bare 844 x 390 window, which no phone page has ([lesson](../lessons/2026-11-05-a-phone-test-read-the-canvas-not-the-page-and-the-layout-never-applied.md)). |
| Resolution scale | `Viewport.scaling_3d_scale` only affects 3D. |
| A button that holds a container | A `Button` never asks its children how tall it is (a script `_get_minimum_size` on a native button is not consulted), a container built outside the tree reports a minimum of 0, and an autowrap `Label` reports a height for the width it has now (1,900 units before its first layout). A focusable card with rows inside it (Deadnight's poster set, #1073) was 8 units tall and the cards stood on each other: compute its height by hand from `font.get_height(size)`, break long text with `get_string_size` and a line feed in the text, and set `custom_minimum_size` before it is added ([lesson](../lessons/2026-11-04-a-button-holding-a-container-did-not-size-to-it.md)). |
| Fitting text | A `Label` with `clip_text` or an ellipsis overrun has a minimum width of 0, so a container squeezes it to nothing: give it `custom_minimum_size.x`; a form row's title column keeps its token minimum for the same reason, so a long title reads "Break between ro..." in a card with no slack (set the overrun to no trimming, and test the cut with the font's own width against the label's, [lesson](../lessons/2026-11-05-a-trimmed-row-title-and-a-form-taller-than-a-phone-card.md)). Fit text from one measurement (size × room / width), since `get_string_size` shapes the string on every call. Test layouts with the longest values the game allows, and with a wide face: `FontVariation.variation_transform` makes a synthetic wide one, so CI needs no font file. |
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
  A headless test sees the overflow only when the screen is under the router's themed stage
  ([lesson](../lessons/2026-11-04-a-headless-layout-test-measured-without-the-stages-theme.md)); the capture tour at
  844 by 390 shows it as the player has it
  ([lesson](../lessons/2026-11-03-a-new-row-pushed-a-form-off-a-phone-held-sideways.md)).
- **Test every input the card takes:** arrow keys and Enter (`get_viewport().push_input` with `InputEventKey`), the
  d-pad and A (`InputEventJoypadButton`), and a tap (`InputEventScreenTouch` plus the emulated mouse button), on the
  card chosen and on the card that is locked.

## A row on a screen that scrolls and focuses its button

A column with `follow_focus` whose screen focuses its button on entry opens scrolled to that button (the lobby: Start,
at the bottom). A control placed above a long list is off screen at first: put what the player must see next to the
button, and print the control's global rect in the capture (a negative y or one past the canvas is the proof). A row
that is pressed on a phone is `MenuLook.TAP_TARGET` units high, the switch inside it too
([lesson](../lessons/2026-11-05-a-new-lobby-row-sat-above-the-fold-of-a-screen-that-opens-scrolled.md)).

## Two option selectors in one row

A setting that is a choice of two or three words shares a form row with its neighbour instead of taking a row of its
own (`bots` and `bot_skill`; `count_multiplier` and `perk_limit`): an `HBoxContainer` of two `UIOptionSelector`s, both
`SIZE_EXPAND_FILL`, linked up and down by `focus_neighbor_*`. A selector cell is about 146 px wide on the desktop
panel: a one-word label fits (`Unlimited`), two words ("Unlimited perks") are clipped under the arrows. The row's hint
says what the words mean. A headless test sees it only under the themed stage (see
[A card taller than its screen](#a-card-taller-than-its-screen)): look at the 1280x720 and 1168x540 captures
([lesson](../lessons/2026-11-03-a-new-match-setting-took-a-sixth-row-and-a-label-too-wide.md)).

## A card taller than its screen

A `Control` with a full-rect `VBoxContainer` in it grows to its content's height, and nothing clips it: a column taller
than its area runs under whatever is below (Deadnight's Loadout tab ran under the key hints and off the right edge,
the Settings screen was 1103 units high on a 1080 canvas and 741 to 1103 on a phone's 540, Play together was 897;
Deadnight issue 980). The canvas is 1080 units high on every desktop window shape (the 1920 x 1080 base stretches with
`expand`, so a taller window is taller and a wider one wider) and 540 on a phone, 960 to 1170 wide: only the interface
size (0.8 to 1.25) and the phone rule change the height, so the sizes to sweep are few.

- **Bound the area, scroll the rest.** `UIFitScroll` (`gds_ui`) is a `UIScroll` that asks for its content's height and
  no more than the screen leaves (`limit`, `margin`, `card`, and `steady` to keep a height between short pages); the
  title and the buttons around it stay on the screen. A tab's column goes in a scroll area the size of its panel
  (`MenuPanel.hold`). A part that must not scroll (the wardrobe's picker list) takes the height its tab leaves
  (`size_flags_vertical` expand, a minimum of 0), never a fixed `custom_minimum_size.y`.
- **A scroll area takes width too.** The theme gives every `ScrollContainer` `hover_room` at each side and the bar a
  track: content that was exactly the panel's width is 54 units wider than its panel once it sits in one. Extend the
  area past the panel by that room (`offset_left`, `offset_right`) or build the rows narrower by `UIScroll.side_room`;
  `SCROLL_MODE_RESERVE` keeps the track in place whether or not the column scrolls.
- **Cap the width as well as the height.** A fixed `custom_minimum_size.x` (1200, 1280) is wider than a phone's
  960-unit canvas: set it from the canvas on `resized`. A row that cannot fit beside its title stacks
  (`UIRow.set_stacked`, `set_widths`); a header (a tab bar and a plate) takes the width in turn.
- **Test it as a sweep of rectangles, in the tree the player has.** Open every screen and tab at each canvas, and fail
  when a control's shown rectangle (cut by the clippers above it: what a scroll hides is not on the screen) crosses
  the screen's edge, its area, the header or the footer, or is wider than a clipper that cannot scroll that way.
  Report the outermost offender only. Deadnight: `game/tests/ui/ui_fit.gd` and `ui_fit_run.gd`, the suite
  `test_ui_fit.gd`, and the capture tour `ui_fit_tour.tscn`, which prints the same sentences beside real pictures.
- **Put the screen under the themed stage.** A screen built under a bare `Control` has no theme: no fonts, no scroll
  room, no bars, and a title 23 units high instead of 83
  ([lesson](../lessons/2026-11-04-a-headless-layout-test-measured-without-the-stages-theme.md)). The router's stage
  (`UIThemeBuilder.build(UITokens.active())`) is what the player has; a headless run then measures the same numbers as
  a window.
- **Answer what a fixture starts.** A screen put in a state that ends in `await some_signal` (the name prompt) is
  answered before it is freed, or the run leaks at exit and CI refuses it
  ([lesson](../lessons/2026-11-04-a-test-left-a-screen-waiting-for-an-answer-and-leaked-at-exit.md)).
- **Not every size is a size.** A phone held upright is covered by the "turn your phone" prompt (test that it is); a
  phone at the Large interface size has a 432-unit canvas and is left out of the sweep. The phone sizes swept are
  844 x 390 (a 1169 x 540 canvas), 932 x 430 and 667 x 375 (the narrowest, 960 x 540)
  ([lesson](../lessons/2026-11-04-menu-panels-ran-under-the-footer-because-nothing-bounded-them.md)).

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

## A part placed from another part's rectangle

A control that must stand beside another (badges by a card) and is placed by code reads the other's `get_global_rect()`.
Do not place it in the other's `item_rect_changed`: when that control sits in a container (or a column anchored to a
screen edge) the signal fires before the container has placed it, so the rectangle read is the old one and the part ends
up a layout step behind (70 units low when the touch layout moved the card). Connect the signal of the control, of its
parent and of the placed part to one function that queues a single deferred placement (a flag so it runs once per layout
pass). Test it by changing the layout and measuring the rectangles after two idle frames
([lesson](../lessons/2026-11-03-a-part-placed-from-a-siblings-rect-read-it-before-the-layout-moved-it.md)).

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

## A grid of items with locked silhouettes

Deadnight's wardrobe (#1065) is the model: tabs on top, an `HFlowContainer` of cells in a `ScrollContainer`, a detail
line under it.

- **A cell is one focus stop and one `Button` drawn by hand** (`flat`, everything in `_draw`): plate, icon, name, a
  check for the chosen one, a padlock for a locked one. Pressing a locked cell refuses (a shake, a refusal sound) and
  never changes the thing being edited; a test sends a click, Enter, Space and the pad's accept at it and compares
  the whole look before and after.
- **Draw the icon from shapes, not a texture** when the set is small and flat: `draw_colored_polygon` for the fills and
  `draw_polyline` for the outline are sharp at any size and nothing has to be held for the draw (the white-square lesson).
  A silhouette is every outline first, twice as wide, then every fill in one colour on top: the inner outlines are
  covered and only the rim stays.
- **Hover and focus must say the same words.** Both connect to one `shown(on)` signal, the screen reads the cell's
  `detail()` into one line, and a cell losing the pointer reads whatever else holds the focus. Do not make the pointer
  grab the focus: `follow_focus` then scrolls the grid under the hand. Test the pointer with `push_input(motion, true)`
  and the focus with `grab_focus()` on a pad run, and compare the two lines.
- **A tab strip shows a page on a press, not when the focus passes it.** The engine's walk from the first row of a grid
  to "the nearest control above" lands on whichever tab is over that cell, which would switch the page under the
  player. Link the first row's top neighbour to the tab on show (the rows are only known after the layout, so do it in
  a deferred call from the grid's `sort_children`) and a tab's bottom neighbour to the page's first cell
  ([lesson](../lessons/2026-11-04-a-tab-that-showed-on-focus-switched-under-the-pad.md)).
- **A cell that is not locked can still do nothing.** Deadnight's "Default colours" cell is dim and says why ("wear a
  costume to give it its own colours back") instead of showing a padlock and `???`: a lock means "not yours yet", an
  off cell means "not now". Press, hover and focus read the same words; the screen reader gets the reason too.
- **A strip that grows a tab must be measured on the phone.** The tenth tab wrapped one tab onto a second row at 844 by
  390, taking the grid's room. The fix was smaller padding and type in the compact layout, and the layout sweep
  (`test_ui_fit.gd`) now shows each wardrobe tab, not only the first one it opens on.
- **Sort by what the player reaches first**, with a stable tie-break (decorate with the index and sort the pairs), so a
  ladder reads from the starting pieces up and a grid with no levels keeps the catalogue's order.

## 3D in a menu

- **A menu's 3D stage is drawn at the window's pixels.** With the canvas stretch a `Control` is 1920 x 1080 whatever the
  window, and a `SubViewportContainer` makes its viewport that size (stretch on) or grows to the viewport's (off):
  1920 x 1080 stretched into a 2560 x 1440 window, soft and stair-stepped. Use a `Control`, a `SubViewport` child and a
  `TextureRect` on its texture, and size the viewport from `get_viewport().get_final_transform().get_scale()` times the
  control's size (cap it, 1440 high), again on `size_changed` of the root
  ([lesson](../lessons/2026-11-03-a-menu-stage-viewport-was-sized-in-canvas-units-not-pixels.md)).
- **A `SubViewport` has its own `msaa_3d`** (the project setting does not reach it): choose it for the look (4x for a
  portrait or a stage; on a phone the pixels are fewer at the real size, so 4x cost less than the old 2x there).
- **An adaptive-quality fallback needs a way back.** Judge over more than one window, climb back when frames recover
  (in seconds, not frames), and back off after a failed climb so it never flickers
  ([lesson](../lessons/2026-11-03-a-quality-fallback-with-no-way-back-kept-the-menu-soft.md)).

## A part at a scale of its own inside a screen

A card that opens over a screen whose window factor must not change (a pause card over a night's HUD) is drawn by a
control with `scale = f` and a size of the holder over `f` (Deadnight `PhoneScale`): its children lay out on the smaller
canvas, text stays sharp, and a press goes through the scale. What reads the window instead of the control is wrong
inside it: a scroll's room (`UIFitScroll.limit`), a tap size in units (divide by the part's scale), the audit
(multiply by the control's global scale). See the [lesson](../lessons/2026-11-05-a-card-over-a-night-needed-its-own-scale-and-everything-read-the-window.md).

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

## Reading a screen under test: the scale it really runs at

- **A phone is a page, and its scale is the screen's.** A phone's web page is a canvas of twice its CSS size (the pixel
  ratio is capped at 2, `PhoneRender`): an 844 x 390 page is a 1688 x 780 window, and `MenuScale.is_phone` reads the
  page (`PageSize`, a touch device under 500 CSS px) as well as the window. The menus and the lobby then have
  `MenuScale.factor(window.size, ui_scale)` (2: a 1169 x 540 canvas, 0.72 CSS px to the unit, on any ratio); a night
  has the interface size alone (`NightScreen._ready`), about 0.36 CSS px to the unit. A capture or reading names the
  page (`UiFitRun.set_window(size, scale, ratio)`, 1688 x 780 at 2 and 2532 x 1170 at 3 for an 844 x 390 page) and a
  HUD place sets `content_scale_factor = ui_scale`, a menu place `MenuScale.factor(...)`; `MenuScale.describe` prints
  which scale a window runs at. The numbers a person measures (smallest text, smallest target, in CSS px) are
  `UiAudit`, in the web probe and in `test_phone_floor.gd`
  ([lesson](../lessons/2026-11-05-a-phone-test-read-the-canvas-not-the-page-and-the-layout-never-applied.md);
  [earlier lesson](../lessons/2026-11-05-a-phone-capture-without-the-phone-scale-showed-the-wrong-layout.md)).
- **Read the night at the canvas, and the menu at the CSS pixel.** A web page of 844 by 390 CSS pixels at a pixel ratio
  of 2 (the cap) is a canvas of 1688 by 780, 0.72 canvas px to the unit in a night (2532 by 1170, 1.08, at a ratio of
  3), 0.36 CSS px; a window of 844 by 390 is the ratio-1 worst case. Read a phone at the canvas and report the worst
  case beside it ([lesson](../lessons/2026-11-05-a-phone-reading-at-the-css-size-overstated-the-fault.md)).
- **A contrast ratio of two colours is not what a thin stroke shows.** Words that must be read on a phone are read from
  the pixels (the place drawn with the words, without, and in one flat colour): the strongest pixel and the median
  letter pixel against its neighbours; a stroke under a pixel has no pixel that is mostly ink
  ([lesson](../lessons/2026-11-05-a-contrast-ratio-of-two-colours-passed-while-the-pixels-were-a-smear.md)).
- **Build a screen under the router's theme.** A test that adds a screen to a bare `Control` has Godot's default font and
  half-height rows; give the host `UIThemeBuilder.build(UITokens.active())` or open the screen through `UIRouter`
  ([lesson](../lessons/2026-11-05-a-screen-built-without-the-routers-theme-measured-a-problem-that-was-not-there.md)).
