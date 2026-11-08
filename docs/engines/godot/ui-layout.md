# UI layout: proving a fit, placing a part, phone pages

<!-- new section: ui-controls.md is at the size limit; the checks that a screen fits, how a HUD part finds free ground and
what a phone page changes had grown into a topic of their own -->

How to show that a screen or a HUD fits, where a part goes when its neighbours move, and what a phone's page changes.
The controls themselves and the sweeps they need are in [UI controls](ui-controls.md) (see [A card taller than its
screen](ui-controls.md#a-card-taller-than-its-screen) and [A card that looks for free
ground](ui-controls.md#a-card-that-looks-for-free-ground)); sending input is in
[Input in UI tests](ui-input-tests.md).

## Proving a fit {#fit}

<!-- new section: ui-controls.md has the fit sweep; what a fit check must ask, and the budgets behind it, had no home -->

- **Approach:** Make a fit check ask every text a row or card draws (title, hint, value, caption), on every tab and
  every page the game has (`UiFitRun.PAGES`, with the extremes of what a phone is), at the fullest content the game can
  produce, for every part of the column and above all the one the player must reach. **Watch out for:** a check was
  written for the text and the screens that had failed: `title_cut()` was asked of the lobby and solo rules only, so a
  phone's Settings showed cut hints and a value touching the scrollbar; a card's own test was green while the Leave
  button below it sat at y 950 on a 864-high screen; a HUD that was clean at 1080p and 1440p had 17 overlaps at
  1536 x 864. **Seen:** Deadnight #1145, 2026-11-04; Deadnight #1275, 2026-11-05 (fix: `UIRow.hint_cut()`,
  `test_settings_phone.gd`, and every part of the column named in the test).
- **Approach:** Measure text a control draws itself (a ticket's note, a caption in a tile) with the same font and size
  the control draws, hold the sum inside the room it leaves, and reserve lines for the longest sentence in the data;
  capture such a screen on its narrowest cell at player size and read it whichever suites pass. **Watch out for:** a
  fit sweep reads the rectangles of controls, and `MenuItemButton` draws its title and note with `draw_string`, so the
  note overprinted the title in the capture only; a locked tile reserved two caption lines for a 132-unit cell and a
  40-character riddle wrapped to four and was covered by the next row's art. **Seen:** Deadnight #1172, 2026-11-05
  (fix: `PlateTile.CAPTION_LINES`, and a test that measures the title and note the button draws).
- **Approach:** Decide a fit from the children's own minimum sizes, or from a sum written down first (canvas less
  margins, card padding and scroll bar against the row's minimum), take the saving from the cheapest line, and let the
  test allow no slack. **Watch out for:** a `Label` is as tall as its font's line, so a 24 px label in a 26 px row made
  it 33 and the sums described heights nothing drew (step the type down until `font.get_height(size)` is at most the
  row, then measure); a column check summed constants and was 6 units short of the chips, a saving sized against the
  widest row missed the card by 4, and a test allowing 8 units of slack had hidden the wrong constant. **Seen:**
  Deadnight #1301, 2026-11-05; Deadnight, 2026-11-04 (fix: `HudPointsStack.height_at(columns)` reads the children;
  a test lays out every party and compares with the drawn column).
- **Approach:** For a scroll area, assert what is in the view after the tab opens and after the first key press into
  it (whole items, nothing cut at the top, scroll still 0) on the smallest page, and keep a height budget (what the
  chrome takes, what is left) in the pull request. **Watch out for:** a fit test asks whether the content stays inside
  the card, and a scroll area passes that at any height, even a 33-unit sliver: the Loadout card opened on a cut label
  and nothing to choose, with every fit and floor test green. **Seen:** Deadnight #1271, 2026-11-05 (fix: the test
  counts whole items in the view, and a panel's first focus is something in view).
- **Approach:** Compute a size from the canvas again whenever the canvas may change (`resized`, when the factor is
  set), and build the thing in a layout test in the page's order (hidden, at the interface size, then shown), comparing
  the rectangles of neighbours (`intersects`). **Watch out for:** `MenuShell` sized its plate once in `_build_chrome`
  from `get_viewport_rect()`, before the phone factor was on the window, so it covered 29 units of the last tab on the
  narrowest page; a height or a text size does not show a cover, and every test set the factor first. **Seen:**
  Deadnight #1271, 2026-11-05 (fix: `MenuPlate.fit` on the factor and on `resized`; `header_overlap` in the probe).

## Placing a HUD part {#placement}

<!-- new section: ui-controls.md has the placement search and a part placed from a rectangle; the rules for neighbours
that come and go, the search and the stick had no home -->

- **Approach:** Keep a part clear of a neighbour that comes and goes by the neighbour's place, not its rectangle at that
  moment: leave a hidden part out of the lists others avoid (`button_boxes`), emit `layout_changed` when it comes or
  goes, put a part that must stay clear beside a column instead of in it, and `await` two idle frames before measuring.
  **Watch out for:** `button_boxes` listed the interact button while it was not drawn and took the smallest page's
  last free column (25 units to spare); a lane put last in a column jumped by the banner's height the frame the banner
  left, and a first test measured a banner 772 units high and a column of width 0. **Seen:** Deadnight #1277,
  2026-11-05; Deadnight #1064, 2026-11-04 (fix: hidden buttons left out; the lane eases beside the column).
- **Approach:** Make a placement search complete and cheap: try the columns whose left edge sits either side of an
  obstacle or the screen, nearest first, and in each column the nearest clear `y` from the obstacles' edges, in both
  directions; measure the strings once a draw; test a corridor and count how many markers a page holds; and let no test
  skip a page without a follow-up issue. **Watch out for:** a hint slid only downward found a free place 520 units
  down, on the ammo card; a search beside each card missed a 344-unit column between cards and buttons and the grid
  test skipped that page; laying the marker out for every try took 300 markers past ten minutes (2000 layouts for
  one). **Seen:** Deadnight #1277, #1230, #1218, 2026-11-05 (fix: `HudMarkers._nearest_clear`, widths measured once a
  draw; 7 ms against 37 ms).
- **Approach:** Keep a place clear by its edges, not by a corner offset times a scale, test it against the thing that
  grows at its largest (parties of one to eight with bots, three touch scales, both hands), and when an issue names a
  place, put the part there first and measure every neighbour that stands at a share of the screen or reads the
  column's height; never move a constant another open issue owns, report the overlap there. **Watch out for:** the
  stick's resting ring (330 right, 390 up) was over the points card, which grows upward with the party, and raising
  the constant moved the first-run hint over the cards; a fingertip-high tag in a bottom-anchored column made it 128
  units taller and put the challenge card over it. **Seen:** Deadnight #1284, #1280, 2026-11-05; Deadnight #1286,
  2026-11-05 (fix: the ring is kept clear by its edges; the tag went to the weapon strip's row).

## Phones {#phones}

<!-- new section: ui-controls.md says what a phone page is; distances a finger needs and a phone capture's pixel ratio
had no home -->

- **Approach:** State a distance a finger travels or needs (a stick's ring and sprint edge, the air between two
  buttons, a tap size) in CSS pixels or millimetres, derive it from `MenuScale.tap_units` and the page's scale, derive a
  tap size on the shortest page that counts as a phone, and test the extremes (narrowest, tallest) and the hit areas,
  not the drawn circles. **Watch out for:** a unit is 0.29 CSS px at interface size 0.8 and 0.45 at 1.25, so 96 units
  was 7 mm on one phone and 11 on another and Pause and Ping were a thumb's width apart; `TAP_TARGET` of 62 units was
  44.8 px on the 844 page and 43.1 on the 667 one, which only an unrun web probe checked; a test with no fingertip lays
  out a different page. **Seen:** Deadnight #1264, 2026-11-05; Deadnight #1289, 2026-11-05 (fix: sizes in CSS
  px, `test_phone_floor` lists the narrowest page).
- **Approach:** Give a capture that stands for a phone the page's pixel ratio (`MenuScale.pixel_ratio = 2.0`), mark
  the first-run hints used when a picture of the HUD is the point, and read sizes in CSS px from the result (the web
  probe's `touch_zones`), not off the picture. **Watch out for:** a desktop window reports a ratio of 1, so
  `tap_units` gave a fingertip half the size (places 22 CSS px, not 44) and the players' column sat 37 units lower than
  on the page, under the hints. **Seen:** Deadnight #1280, #1301, 2026-11-05 (fix: the ratio is set in the capture
  scene; numbers come from the web export in Chrome as a phone).
