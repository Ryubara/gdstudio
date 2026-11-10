# UI controls

How custom-drawn controls behave in Godot 4.7, learned building GDStudio's UI addon (`gds_ui`). Proving that a screen
fits, placing a HUD part and phone pages are in [UI layout](ui-layout.md); sending input to a screen in a test and what
a suite leaves for the next are in [Input in UI tests](ui-input-tests.md).

| Topic | What we learned |
| --- | --- |
| Drawn controls | Extend the engine control for its behaviour (HSlider, Button), empty its styleboxes in a theme variation, and draw in `_draw` with springs. A script `_draw` on a Button runs after the native draw, so a fill drawn there paints over the text (found by capture, not in the docs): draw on a child control with `show_behind_parent`. |
| Tweens on a disabled or freed node | A node whose `process_mode` is `PROCESS_MODE_DISABLED` (a screen a router covers) never advances a tween created on it, so its animation never runs. A tween on a node that is freed is killed and its `finished` signal never fires, so an `await` on it waits forever. Create transition tweens on a node that stays enabled and outlives the screens (the router's stage), and check `is_instance_valid` after every await. |
| Screen-reading shaders | `hint_screen_texture` makes the renderer copy the back buffer: +0.18 ms at 1080p and +12 MB for a full-screen grade ([Compatibility lighting](compat-lighting.md#full-screen-post-shader)), and it is the shader feature most likely to differ on a mobile or WebGL2 GPU. A screen transition does not need it: make it procedural (hash noise) over a colour the shader owns, close it over the old screen, swap behind it, then open. |
| Clear colour | Set `RenderingServer.set_default_clear_color` to the UI's background token. A fade or a screen swap that passes through "nothing" shows the engine's default grey, which no token owns. |
| A transition checklist | A pop is not a push played backwards: the screen that leaves must be on top, and only the transition may decide layering (never the stage's child order). For each transition capture the push **and** the pop, free the outgoing, the incoming and the popped screen mid-transition and check the router is idle, queue calls during it and check they run in order, and run it with reduced motion on. The list is in the addon's README (`godot/addons/gds_ui/README.md` in the kit). |
| Slider hit area | HSlider hit-tests with the grabber icon's width, so the theme's invisible grabber must be as wide as the drawn thumb. Check with a real InputEventMouseButton: a click at 60% of the travel gave 1.85 of 0.1 to 3.0. |
| An overlay in a padded container | A `PanelContainer` (any container with content margins) lays out every child inside the margins, an overlay such as a border included, so padding for the words shrinks the border with them. Give the overlay its own room: draw it outside its rectangle by the margin (a `grow` on the control; drawing outside the rect is allowed), and take the room from the content, not from the container, so the row keeps its width. |
| Invisible textures | Never a PlaceholderTexture2D: it draws a magenta checker in game. Use a transparent ImageTexture. |
| Runtime UI scale | `Window.content_scale_factor` resizes CanvasLayer stages and anchored controls; with `canvas_items` stretch the visible area is the base size divided by the scale. Avoid autowrap Labels in rows: they inflate containers. A phone capture needs the game's own factor (`MenuScale.factor(window.size, 1.0)`), or it shows the design canvas shrunk, not the phone's layout. **On a web page the window is the canvas in device pixels** (the ratio is capped at 2: an 844 x 390 phone page is 1688 x 780), so "a phone" is the page's short side in CSS pixels, not the window's; a test or capture names a page, never a bare 844 x 390 window, which no phone page has. A desktop window reports a pixel ratio of 1, so a phone capture sets the ratio too ([UI layout](ui-layout.md#phones)). |
| A drag that starts on a button | `Button` stops the pointer (`MOUSE_FILTER_STOP`), so a touch that lands on it, with its drag steps and the emulated mouse, never reaches the `ScrollContainer` around it: the card scrolls from its words and margin only. A button that passes the pointer (`PASS`) lets the card scroll, but with nothing above it that stops the pointer the click goes on to `_unhandled_input` (a HUD board's button whose ancestors all ignore the pointer would give the player the pointer lock), and the engine's `ScrollContainer` is itself `PASS`. So a button passes only while a `ScrollContainer` set to `STOP` is above it (decided on `tree_entered`), the card gets a `scroll_deadzone` for a touch that starts on a button (the engine's is 0: the first hair of movement scrolls and takes the press; Deadnight uses 10 CSS px), and the test clicks and taps the button outside a card too and spies on `_unhandled_input`. Headless cannot scroll by touch (`DisplayServer.is_touchscreen_available()` is false): test what the card receives and measure the scroll in a web probe with `Input.dispatchTouchEvent`. |
| A button a finger lifted from stays lit | A finger that lifts sends no mouse exit, so the engine keeps the button it lifted over hovered (pale, grown by the hover spring) until the next touch, in a card or not (a tap on Copy the link: 70 apart from rest by the colour of its fill, 2 after the fix). Decide it from the event that lifted, never from "is this a phone": an `InputEventScreenTouch` release starts a timer, and when it is due (after the press spring has settled, 0.3 s) the button, if it still exists and is hovered, has its `mouse_filter` set to `IGNORE` and back, which makes the engine send the exit; a mouse release does nothing, so a desktop mouse keeps its hover, and a real mouse motion or a new touch calls the timer off. Hold the button by `get_instance_id()` in the timer, never an `await` on a button a press may free (it prints an error). Measure it with the colour of the fill in a web export through real touches, in a card and outside one; a headless run is not a touch screen. |
| Resolution scale | `Viewport.scaling_3d_scale` only affects 3D. |
| A button that holds a container | A `Button` never asks its children how tall it is (a script `_get_minimum_size` on a native button is not consulted), a container built outside the tree reports a minimum of 0, and an autowrap `Label` reports a height for the width it has now (1,900 units before its first layout). A focusable card with rows inside it (Deadnight's poster set, #1073) was 8 units tall and the cards stood on each other: compute its height by hand from `font.get_height(size)`, break long text with `get_string_size` and a line feed in the text, and set `custom_minimum_size` before it is added. |
| Fitting text | A `Label` with `clip_text` or an ellipsis overrun has a minimum width of 0, so a container squeezes it to nothing: give it `custom_minimum_size.x`; a form row's title column keeps its token minimum for the same reason, so a long title reads "Break between ro..." in a card with no slack (set the overrun to no trimming, and test the cut with the font's own width against the label's). Fit text from one measurement (size × room / width), since `get_string_size` shapes the string on every call. Test layouts with the longest values the game allows, and with a wide face: `FontVariation.variation_transform` makes a synthetic wide one, so CI needs no font file. |
| Baselines and label height | A Label is as tall as the font's line (about 1.4 times its size), not its capitals: size a box from that. `SIZE_SHRINK_END` aligns the bottoms of boxes, not baselines: put two sizes on one baseline with `baseline - font.get_ascent(size)` for each, or lift the smaller by the difference of the descents. |
| One-shot 3D portrait in a HUD | A `SubViewport` with `own_world_3d`, the model, a camera and lights, `render_target_update_mode = UPDATE_ONCE` two frames after the model enters (its idle clip must pose it), shown by a `TextureRect` on `viewport.get_texture()`; it costs nothing after that frame. |

Game write-ups: Deadnight's `docs/research/ui-foundation.md` and `docs/research/settings.md`.

## Where `gds_ui` is edited {#where}

The addon has one source: the kit's own Godot project, `godot/addons/gds_ui/`. A game never edits its copy. `gds sync`
writes the addon into each game's `game/addons/gds_ui/` (the same `res://addons/gds_ui/` path, so nothing in a game
changes), records every file's hash in the game's `.claude/gds-sync.json`, and `gds sync <game> --check` fails when a
file differs, is missing, or sits in the addon's folder without being in the kit ([Sync](../../studio/sync.md#addons)).
It is a
tracked copy, not an untracked install like GdUnit4: shipped game code depends on it, and a game's CI must not need a
second fetch to build.

To change it:

1. Edit it in the kit and run the addon's suites (below) in a kit pull request. Name no game in the addon: a
   game's skin is a `UITokens` resource the game owns, a game's screens extend `UIScreen`.
2. After it merges, run `uv run --project python gds sync <workspace>/repos/<game>` for each game, and commit the
   result in a pull request of that game (the game's own suites are its proof that the new version fits).

**Its tests.** `godot/tests/gds_ui/` holds the suites that need nothing but the addon (the router and its robustness,
the tokens and the restyle, every component, glyphs, the spring and the theme), with the small helpers they share
(`RouterFixture`, `WidgetEvents`, `InputFixture`), and `godot/tests/captures/` the scripted tours of the controls and
glyph sheets. They run in the kit's Godot project with the pinned Godot and GdUnit4, which `gds workspace init`
installs untracked into `godot/` like into a game:

```sh
godot=$(uv run --project python gds tool path godot)
"$godot" --headless --path godot --import        # once, and after adding a class_name
"$godot" --headless --path godot -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd -a res://tests -c --ignoreHeadlessMode
```

The kit's CI runs the same two commands (the `godot` job). A suite that needs a game's own classes (a screen, the page
size, the settings autoload) stays in that game: Deadnight keeps its menu, touch-slip and sound-role suites. The project
declares `ui_accept` (Enter, Space, pad A and Start) and `ui_cancel` (Escape, pad B), which the controls act on; the
tests press those keys and buttons.

## A control that draws outside its rect {#a-control-that-draws-outside-its-rect}

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

- **Approach:** Test a control that draws outside its rect in its drawn states (hovered, focused, pressed) against its
  nearest clipping ancestor, at every canvas size. **Watch out for:** `UIButton` grows 3.5% on hover as paint, not
  layout, and the lobby put edge-to-edge buttons in a `ScrollContainer`, which clips at its rect; the layout tests read
  only resting rects. **Seen:** Deadnight #628, 2026-11-02 (fix: deadnight #650 added the drawn-state test).

## A picker of cards in a form row {#a-picker-of-cards-in-a-form-row}

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
  A headless test sees the overflow only when the screen is under the router's themed stage; the capture tour at
  844 by 390 shows it as the player has it.
- **Test every input the card takes:** arrow keys and Enter (`get_viewport().push_input` with `InputEventKey`), the
  d-pad and A (`InputEventJoypadButton`), and a tap (`InputEventScreenTouch` plus the emulated mouse button), on the
  card chosen and on the card that is locked.

## A row on a screen that scrolls and focuses its button {#a-row-on-a-screen-that-scrolls-and-focuses-its-button}

A column with `follow_focus` whose screen focuses its button on entry opens scrolled to that button (the lobby: Start,
at the bottom). A control placed above a long list is off screen at first: put what the player must see next to the
button, and print the control's global rect in the capture (a negative y or one past the canvas is the proof). A row
that is pressed on a phone is `MenuLook.TAP_TARGET` units high, the switch inside it too.

## Two option selectors in one row {#two-option-selectors-in-one-row}

A setting that is a choice of two or three words shares a form row with its neighbour instead of taking a row of its
own (`bots` and `bot_skill`; `count_multiplier` and `perk_limit`): an `HBoxContainer` of two `UIOptionSelector`s, both
`SIZE_EXPAND_FILL`, linked up and down by `focus_neighbor_*`. A selector cell is about 146 px wide on the desktop
panel: a one-word label fits (`Unlimited`), two words ("Unlimited perks") are clipped under the arrows. The row's hint
says what the words mean. A headless test sees it only under the themed stage (see
[A card taller than its screen](#a-card-taller-than-its-screen)): look at the 1280x720 and 1168x540 captures.

## A card taller than its screen {#a-card-taller-than-its-screen}

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
  room, no bars, and a title 23 units high instead of 83. The router's stage
  (`UIThemeBuilder.build(UITokens.active())`) is what the player has; a headless run then measures the same numbers as
  a window.
- **Answer what a fixture starts.** A screen put in a state that ends in `await some_signal` (the name prompt) is
  answered before it is freed, or the run leaks at exit and CI refuses it.
- **Not every size is a size.** A phone held upright is covered by the "turn your phone" prompt (test that it is); a
  phone at the Large interface size has a 432-unit canvas and is left out of the sweep. The phone sizes swept are
  844 x 390 (a 1169 x 540 canvas), 932 x 430 and 667 x 375 (the narrowest, 960 x 540).

- **Approach:** Run the fit sweep (`test_ui_fit.gd`) on any menu change: every tab and screen at desktop, web and phone
  sizes and interface scales with the longest content, cards bounded with `UIFitScroll`, tab columns with
  `MenuPanel.hold`, test screens opened under the themed stage. **Watch out for:** menu panels were full-rect columns or
  centred cards that grew with their content and nothing bounded or scrolled them (the Loadout ran 47 units under the
  footer), and layout tests built screens outside the theme, so text measured too small. **Seen:** Deadnight #980,
  2026-11-04 (fix: the sweep).

## Touch controls {#touch-controls}

Touch controls press the game's existing input actions, so gameplay code does not fork. `Input.emulate_mouse_from_touch`
is off while they show, or every touch also clicks. Tests inject `InputEventScreenTouch` and `InputEventScreenDrag`
with `Input.parse_input_event`, in window pixels: multiply canvas positions by the viewport's `get_final_transform()`
first. On the web, set `viewport-fit=cover` and block page scroll, zoom and the long-press menu. Deadnight's design
and what its build showed: `docs/research/mobile-controls.md` there.

A new HUD part must be tested against the touch buttons too (a list of kept cards in the layout test) and captured on a
phone: the right thumb's corner is full, and rectangle tests between HUD parts do not see it. A HUD part's `refresh`
must not need the tree: `global_transform` of a node not yet inside it is an error and an identity.

A control for a verb the HUD already shows is a place of the HUD, not a button of the layer: the layer asks the HUD where
its places are (`TouchControls.zones`) and presses the action of the first that holds the finger, so the order of the
list is the rule (put the narrowest place first). Measure a place against every neighbour that stands at a share of the
screen or reads a column's height (the stick's resting ring, the challenge card, the markers) with the touch layout on,
before building it: a fingertip-high part in a card column makes the column a fingertip taller. A word in a
screen corner is darker than its tokens say: the film's vignette takes a corner to about 0.6 of its brightness, so
measure its contrast on a capture. A fit method that
moves a child of a container does it deferred and only when it must: `move_child` is refused while the container is
setting up its children. A test that names
"every first-run hint" as the list's constant breaks when a hint shows only under a condition.

- **Approach:** Prove phone input in the real web build in a mobile-emulated browser sending `Input.dispatchTouchEvent`:
  each finger alone does only its own job, and a drag of N px turns by the designed angle; keep a GdUnit test that
  injects the stray mouse motion as the desktop guard. **Watch out for:** a browser reports a finger as touch and as
  pointer events, and Godot's web runtime reads every `pointermove` as a mouse motion in device pixels, so the move
  stick turned the view and a look drag turned 1.43 rad against 0.41; synthetic touch tests in the desktop runner all
  passed. **Seen:** Deadnight #470, 2026-11-02 (fix: deadnight #480).
- **Approach:** Build touch controls as `Control` nodes of their own scene, never a `_draw` of one canvas: the stick's
  rings and knob, each button (a node you drag and anchor, its action and word exports), two zones that decide which
  finger does what, and a safe-area box the script sets from the device's safe area and `margin`. Make the script `@tool`
  so the editor shows the controls even when `show_mode` hides them, and let it only read the nodes' places. **Watch out
  for:** the first version drew everything in `_draw` of an empty `CanvasLayer` (nothing in the scene, slots hidden in an
  angle table); a `@tool` script must not touch `Input` or `DisplayServer` at edit time; the saved sizes must equal what
  the script computes or every open dirties the scene. The 18 finger tests passed unchanged.
  **Seen:** gdstudio #831, 2026-11-08 ([checklist](new-game.md#template-checklist)).
- **Approach:** Start a new device's controls from the reusable `TouchControls` of the 3D Blank template (a floating
  stick, a look drag, buttons that press the game's actions; the settings are exports) and prove it as the template did:
  GdUnit4 with two fingers, a drag whose `relative` is wrong and mouse motion, then the web export in a phone-sized
  browser through `Input.dispatchTouchEvent`. **Watch out for:** in a CDP `touchEnd` the points listed are the ones that
  lift, so the harness lifted the stick with the look finger until it listed only the finger that went up; and a layer
  that reads `InputEventScreenDrag.position` and never `relative` turned the view by exactly the designed 33.2 degrees
  with a second finger down. **Seen:** gdstudio #821, 2026-11-08
  ([The 3D Third Person template](third-person-template.md#touch-controls)).
- **Approach:** Give every touch control test a second finger on another control at the same time, run a two-finger case
  in the live probe, and read per-finger positions, never `InputEventScreenDrag.relative`. **Watch out for:** the tests
  drove one finger at a time; in Chrome with two fingers down a finger's first `relative` is measured from the origin or
  the other finger's press (1454 px for a 100 px drag) and `velocity` is stale for three drags: a 2.42 rad turn against
  0.41 designed. **Seen:** Deadnight #497, 2026-11-02 (fix: per-finger positions (Deadnight #506)).
- **Approach:** Check a control that arrives at its own rate and drives a drawn view in the browser for the per-frame
  turn under a steady hold (still frames, back steps, variation), with the page at phone speed, and keep it in a test.
  **Watch out for:** smoothness belongs to the view per drawn frame: the touch layer turned the view per finger sample,
  so at 175 fps a steady drag turned one frame in three, and the earlier touch tests checked only the total turn.
  **Seen:** Deadnight #598, 2026-11-02 (fix: the look waits and turns the view a share per frame).
- **Approach:** Make every touch button under the look thumb also look while dragged: a new row in `TouchLayout.BUTTONS`
  looks unless it says otherwise (`DRAG_OWNERS`), and a test walks the table and holds each verb (grenade, aim, fire,
  repair) on every device while turning the view and moving. **Watch out for:** a phone has two thumbs, so a held button
  takes the only free one; Grenade, held for the whole cook, and later Reload and Jump sat outside a per-button
  allow-list and turned nothing, and the tests pressed for a tick without turning. **Seen:** Deadnight #599, 2026-11-02;
  Deadnight #1277, 2026-11-05 (fix: the list is derived from the table).
- **Approach:** Design a device's controls from its own inputs and what its screen already shows: before building, list
  every action and every element and give each a verdict (keep, make the existing element tappable, drop as a
  duplicate), and prove a rule the player expects everywhere (reload at 0) through each device's real input. **Watch out
  for:** the phone was the desktop with a button per action, so a swap button repeated the tappable weapon display; each
  button passed its size and safe-area tests, which cannot see too many or a duplicate, and the phone was fixed one
  complaint at a time. **Seen:** Deadnight #1275 to #1280, 2026-11-05 (fix: a control count and a duplicate check are a
  design review).

## A part placed from another part's rectangle {#a-part-placed-from-another-parts-rectangle}

A control that must stand beside another (badges by a card) and is placed by code reads the other's `get_global_rect()`.
Do not place it in the other's `item_rect_changed`: when that control sits in a container (or a column anchored to a
screen edge) the signal fires before the container has placed it, so the rectangle read is the old one and the part ends
up a layout step behind (70 units low when the touch layout moved the card). Connect the signal of the control, of its
parent and of the placed part to one function that queues a single deferred placement (a flag so it runs once per layout
pass). Test it by changing the layout and measuring the rectangles after two idle frames.

- **Approach:** Place a part beside another by where the first is drawn: read the font's glyph outlines
  (`LevelTag.digit_span`) and the art's own ink, keep the arithmetic in one helper every place calls, and prove it from
  pixels at the sizes players have (`test_level_ink.gd`). **Watch out for:** digits and icon were placed from their own
  boxes, but digits sit at cap height above room for a descender and the icon's art fills 0.44 to 0.46 of its cell; each
  place nudged it its own way, judged by rectangles, so the bottom-left box (icon 7 px high) was found by eye. **Seen:**
  Deadnight #1161, 2026-11-04 (fix: the helper and the pixel test).
- **Approach:** Take the middle of a control that may sit under a scaled parent as `control.get_global_transform() *
  (control.size * 0.5)`. **Watch out for:** `get_global_rect()` is the global position and the unscaled size, so for a
  menu laid out at a phone's factor of 2 it gave a point half a control away from the middle and a probe tapped the
  gap beside every button. **Seen:** gdstudio #881, 2026-11-10 (`UiProbeFields`, tapped by `menu_smoke.py`).

## A card that looks for free ground {#a-card-that-looks-for-free-ground}

A card that must stand clear of columns that grow (the challenge prompt beside the players' column, Deadnight #1299)
does not get a share of the screen's height and a hope: `ChallengeFit.place` is pure geometry over the room, the usual
place and two lists of boxes. `hard` boxes are the cards that stay up, the corner columns whole (so a tag added to a
column later is in its box), the box round the middle and the touch buttons (`Hud.markers.held`, which `NightScreen`
sets from the touch layer); `soft` boxes are what comes and goes (feeds, banner, lane, the gains' whole stretch). It
returns the nearest place to the usual one that misses both lists, then one that misses the hard boxes, then the usual
place. Three things bit:

- A container's minimum size is not the card's height until the layout runs: measure from the parts (lines times
  `get_line_height()`) and `reset_size()` on a width change.
- A hidden part's rectangle is not where it draws: work the place out from what places it.
- The columns, the buttons and the cards settle over several frames, so a placement made once, from signals, is a
  layout step behind: place it again each frame the card shows, with a key (boxes, words, size) that makes an unchanged
  frame cost nothing.

Test it with the busiest night on every page: eight people and the bots on top, every perk, a feed, a prompt, a card of
the lane, both hands and every interface size, reading the boxes of the real touch layer, and with a tag-high block
added to the column.

## Animating a container's children {#animating-a-containers-children}

- **Never read a container child's position in the frame it was shown.** A `Container` sorts its children in a
  deferred call that runs after `SceneTree.process_frame` is emitted, and input is handled before that signal, so
  `await process_frame` from a click resumes before the sort (unless a physics step flushed it first). A page never
  shown has its rows at (0, 0). Read positions two frames after the change, stop the previous tween of the same
  control, and `queue_sort()` the container when the tween ends.
- **Reproduce with real input**: `Input.parse_input_event`, not a direct call, and `Engine.physics_ticks_per_second = 1`
  so no physics step hides the race.

- **Approach:** Test UI motion through real input events, at low and high physics tick rates, switching every tab in
  every order mid-transition, and fail on overlapping rows. **Watch out for:** an entrance that moves a container's
  children depends on when the container lays them out; `UIMotion.stagger_in` read each row's position one frame after
  the tab showed, before the deferred sort, and it was only ever tested from a script, so the settings rows sometimes
  collapsed into each other. **Seen:** Deadnight, 2026-11-01 (fix: positions are read after the sort, and the real-input
  test holds it).

## Menus under test {#menus-under-test}

- **Transparent is not unreachable.** A control at `modulate.a = 0` is still focusable and clickable. While a menu's
  items are hidden or entering, set `mouse_filter` to ignore and `focus_mode` to none, keep the old values, and give
  them back when the entrance ends.
- **Headless mouse in GdUnit4.** The window is 64 x 64 pixels, so mouse events sent with `Input.parse_input_event` land
  outside it. Send them with `get_viewport().push_input(event, true)`; keys still go through
  `Input.parse_input_event`. The test runner also keeps a full-window `Stage` control, so a screen added as a child of
  the test sits under it and `gui_get_hovered_control()` is the `Stage`: add the screen to a `CanvasLayer` (layer 100),
  set `get_window().size` to the design size before instancing it, and click at
  `control.get_global_transform_with_canvas() * local_point`. Pad presses are in
  [Input in UI tests](ui-input-tests.md#sending).
- **Captures of a tour scene.** Await each step's note before the next: a coroutine called without `await` carries on
  and the PNG is taken a few frames late.

- **Parsed input is buffered.** After `Input.parse_input_event`, call `Input.flush_buffered_events()` and wait two
  frames before reading action state.
- **Counts sit in containers beside their text**, never at a hand-measured offset: the offset breaks with the next
  font, scale or translation (Deadnight #466).
- **A centred panel is measured in its tallest state at 720 high.** A `CenterContainer` panel grows with its content
  and runs off a 720-high frame (a Discord Activity, a laptop) when every optional line shows (the Together invite
  panel, the lobby): put side-by-side buttons in an `HBoxContainer`, ellipsise one-line text, wrap the content in a
  `ScrollContainer` capped at the viewport height minus the panel's margin with `follow_focus = true`, and call
  `ensure_control_visible` two frames after showing a field the player must reach. Test the panel's size in a
  `SubViewport` of 1280 x 720 with every optional line shown.

- **Approach:** Press every action as the first input on the live screen, on a pad (device 0 and another id) and in the
  web build with a virtual pad, and test anything bound to a `ui_*` button on a screen with no focused control. **Watch
  out for:** Start is bound to `pause` and `ui_accept`, and the UI router spends the first focus key on focusing the top
  screen, so every Start in a running night was eaten; a Start resume then waited for pointer lock, which a browser
  never grants to a gamepad button. **Seen:** Deadnight #494, 2026-11-02 (fix: only the mouse waits for pointer lock
  (Deadnight #519)).
- **Approach:** Clear the input router before any test that sends mouse or touch input, and run a new input test inside
  its whole folder. **Watch out for:** UI input tests passed alone and failed in the folder run, because a menu an
  earlier suite left on the router took the clicks (a full-rect `STOP` control) or, later, its entrance timer took the
  focus under load. **Seen:** Deadnight #346, 2026-11-01; Deadnight #1037, 2026-11-04 (fix: CI, then running the suites
  in order, found it; a scan test fails a suite that shows a screen without `RouterFixture.clear`; more in
  [Input in UI tests](ui-input-tests.md#leaks)).

## Focus and the pad {#focus}

<!-- new section: focus walks, the pad's accept and cancel and a tab switch had no home; the grid section covers one case
of it -->

- **Approach:** Set `focus_neighbor_*` by hand on the ends of a screen's column (strip, first row, ..., last row,
  footer), refresh them on every tab switch, grab focus on the new tab's button, and test with
  `find_valid_focus_neighbor` after two idle frames (it needs a layout). **Watch out for:** Godot picks the next focus by
  geometry, so Down from a left-aligned tab button went to the footer's Reset directly below it, never to a row in the
  column to its right, and a tab switch hides the focused control, which drops focus to null. **Seen:** Deadnight,
  2026-11-01 (fix: neighbours by hand and a focus walk in the settings tests).
- **Approach:** Declare `ui_accept` and `ui_cancel` with their pad buttons in `project.godot` (the defaults plus joypad
  A and Start for accept, B for cancel, device -1), and test with real `InputEventJoypadButton` events through the
  input path. **Watch out for:** in Godot 4.7.2 `ui_accept` is Enter, Kp Enter and Space and `ui_cancel` is Escape; only
  the focus directions have joypad events, so the D-pad moved focus and A did nothing, while a test that called
  `pressed.emit()` or sent keys never noticed. A project that copies the UI suites needs the same two actions. **Seen:**
  Deadnight, 2026-11-01; gdstudio, 2026-11-07 (fix: the project file declares both; the kit's project declares the same
  two and its CI imports before the GdUnit run, since a new `class_name` is known only after an import).

## Controls built in code {#built-in-code}

<!-- new section: the engine defaults of a Control made by `new()` and of a Tween had no home -->

- **Approach:** Use `set_anchors_and_offsets_preset(PRESET_FULL_RECT)` for any Control built in code. **Watch out
  for:** `set_anchors_preset` changes only the anchors and keeps the control's current rect, so a freshly made Control
  stays 0 x 0 and markers and a crosshair drawn as `size * fraction` all landed at (0, 0) with no error. **Seen:**
  Deadnight, 2026-11-01 (fix: the full-rect HUD overlay uses the preset with offsets).
- **Approach:** Return a valid tween from a motion helper even when motion is reduced: add `tween.tween_interval(0.0)`
  before returning one you made but gave no step. **Watch out for:** a tween with no Tweeners prints `Tween (bound to
  ...): started with no Tweeners`, which the shake under reduced motion did on every refused action. **Seen:**
  Deadnight, 2026-11-01 (fix: `UIMotion.shake` adds the empty interval).

## A grid of items with locked silhouettes {#a-grid-of-items-with-locked-silhouettes}

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
  a deferred call from the grid's `sort_children`) and a tab's bottom neighbour to the page's first cell.
- **A cell that is not locked can still do nothing.** Deadnight's "Default colours" cell is dim and says why ("wear a
  costume to give it its own colours back") instead of showing a padlock and `???`: a lock means "not yours yet", an
  off cell means "not now". Press, hover and focus read the same words; the screen reader gets the reason too.
- **A strip that grows a tab must be measured on the phone.** The tenth tab wrapped one tab onto a second row at 844 by
  390, taking the grid's room. The fix was smaller padding and type in the compact layout, and the layout sweep
  (`test_ui_fit.gd`) now shows each wardrobe tab, not only the first one it opens on.
- **Sort by what the player reaches first**, with a stable tie-break (decorate with the index and sort the pairs), so a
  ladder reads from the starting pieces up and a grid with no levels keeps the catalogue's order.

## 3D in a menu {#3d-in-a-menu}

- **A menu's 3D stage is drawn at the window's pixels.** With the canvas stretch a `Control` is 1920 x 1080 whatever the
  window, and a `SubViewportContainer` makes its viewport that size (stretch on) or grows to the viewport's (off):
  1920 x 1080 stretched into a 2560 x 1440 window, soft and stair-stepped. Use a `Control`, a `SubViewport` child and a
  `TextureRect` on its texture, and size the viewport from `get_viewport().get_final_transform().get_scale()` times the
  control's size (cap it, 1440 high), again on `size_changed` of the root.
- **A `SubViewport` has its own `msaa_3d`** (the project setting does not reach it): choose it for the look (4x for a
  portrait or a stage; on a phone the pixels are fewer at the real size, so 4x cost less than the old 2x there).
- **An adaptive-quality fallback needs a way back.** Judge over more than one window, climb back when frames recover
  (in seconds, not frames), and back off after a failed climb so it never flickers.

- **Approach:** Capture a 3D view in a menu in a real window at two resolutions with its viewport size printed, and run
  an adaptive-quality fallback in a real window with a load that ends: it must climb back, in seconds and with a
  backoff, before it ships. **Watch out for:** a stretched `SubViewportContainer` drew the stage at the 1920 x 1080
  canvas, not the window's pixels, its `msaa_3d` was its own, and the governor dropped to half resolution after one slow
  window for the whole session. **Seen:** Deadnight #893, 2026-11-03 (fix: deadnight #920 and gdstudio #439).

## A part at a scale of its own inside a screen {#a-part-at-a-scale-of-its-own-inside-a-screen}

A card that opens over a screen whose window factor must not change (a pause card over a night's HUD) is drawn by a
control with `scale = f` and a size of the holder over `f` (Deadnight `PhoneScale`): its children lay out on the smaller
canvas, text stays sharp, and a press goes through the scale. What reads the window instead of the control is wrong
inside it: a scroll's room (`UIFitScroll.limit`), a tap size in units (divide by the part's scale), the audit
(multiply by the control's global scale).

## A menu over a live game {#a-menu-over-a-live-game}

- **Do not push a screen over a game that must keep running.** `UIRouter` disables the screen it covers
  (`process_mode = DISABLED`), which is right for a solo night and wrong for a multiplayer one (the link is no longer
  read). Hold the sub-screen (settings) as a child of the menu instead, with a `closed` signal for its Back, and take
  Esc, B and Start in the owner: the child's own `ui_cancel` must go back one step, not resume
  (Deadnight #471, 2026-11-02: a test joins a real server over loopback, opens the menu and the settings, and
  checks the server's tick still climbs).
- **Solo stops the simulation, online it does not**: only the player's controls go off, and the card says so
  ("Menu: the night goes on around you", not "Paused").
- **A solo game that pauses behind its menu** opens it through one host node, not as a router screen: [Menus over a
  game](menus.md#screen-host).
- **In a test, wait for the router only while it is busy** (`if UIRouter.busy: await UIRouter.idle`): the signal is not
  replayed to a waiter that comes after it.

- **Approach:** Give every overlay that hides HUD state one way to undo it, called by every path that closes the
  overlay, and test a screen's first running frame through every entry route (solo, join, resume, the Activity). **Watch
  out for:** the Joining card hid the reticle, the scoreboard and the touch layer; a finished online join only hid the
  card and only Resume restored them, so every online join started with no crosshair. **Seen:** Deadnight #529,
  2026-11-02 (fix: one restore used by every close;
  `test_night_crosshair.gd` joins over a real loopback socket and checks the first running frame).

## Reading a screen under test: the scale it really runs at {#reading-a-screen-under-test-the-scale-it-really-runs-at}

- **A phone is a page, and its scale is the screen's.** A phone's web page is a canvas of twice its CSS size (the pixel
  ratio is capped at 2, `PhoneRender`): an 844 x 390 page is a 1688 x 780 window, and `MenuScale.is_phone` reads the
  page (`PageSize`, a touch device under 500 CSS px) as well as the window. The menus and the lobby then have
  `MenuScale.factor(window.size, ui_scale)` (2: a 1169 x 540 canvas, 0.72 CSS px to the unit, on any ratio); a night
  has the interface size alone (`NightScreen._ready`), about 0.36 CSS px to the unit. A capture or reading names the
  page (`UiFitRun.set_window(size, scale, ratio)`, 1688 x 780 at 2 and 2532 x 1170 at 3 for an 844 x 390 page) and a
  HUD place sets `content_scale_factor = ui_scale`, a menu place `MenuScale.factor(...)`; `MenuScale.describe` prints
  which scale a window runs at. The numbers a person measures (smallest text, smallest target, in CSS px) are
  `UiAudit`, in the web probe and in `test_phone_floor.gd`.
- **Read the night at the canvas, and the menu at the CSS pixel.** A web page of 844 by 390 CSS pixels at a pixel ratio
  of 2 (the cap) is a canvas of 1688 by 780, 0.72 canvas px to the unit in a night (2532 by 1170, 1.08, at a ratio of
  3), 0.36 CSS px; a window of 844 by 390 is the ratio-1 worst case. Read a phone at the canvas and report the worst
  case beside it.
- **A contrast ratio of two colours is not what a thin stroke shows.** Words that must be read on a phone are read from
  the pixels (the place drawn with the words, without, and in one flat colour): the strongest pixel and the median
  letter pixel against its neighbours; a stroke under a pixel has no pixel that is mostly ink.
- **Build a screen under the router's theme.** A test that adds a screen to a bare `Control` has Godot's default font and
  half-height rows; give the host `UIThemeBuilder.build(UITokens.active())` or open the screen through `UIRouter`.
- **A container puts its child's scale back to one.** `Container.fit_child_in_rect` resets the child's rotation and
  scale at every sort, so a `scale` set on a node inside a `CenterContainer` or a box holds until the next layout.
  Scale or move the node above it instead, about its middle (`pivot_offset`), and read the result from the global
  transform.
