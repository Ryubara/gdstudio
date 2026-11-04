---
areas: [godot-ui, general]
---
# Words over art kept their contrast by flattening the art

2026-11-04

- **Saw:** Deadnight #1070 put a calling card behind a player's HUD box. The first version laid a veil of the seat's
  colour over the card and pulled any part darker than 4.5:1 against the ink toward the veil's colour. The test passed
  for every card and seat colour, and the capture showed flat brown boxes: the card was gone and so was the armband's
  colour.
- **Cause:** contrast was made a property of the background (every pixel behind the words), so the cheapest way to meet
  it was to remove the picture. A number that passes is not a look that works; the capture was the check, and it was
  taken only after the test was green.
- **Fix:** keep the picture and give the words their own ground. The points, the biggest numerals, sit on a tab of the
  seat's own colour (exactly the contrast they had without a card); the small words get an outline in that colour
  (`HudLabel.halo_colour`), so each glyph sits on the colour its ink was chosen for, whatever the art behind it is.
  Check for next time: when text goes over a picture, look at one capture of the worst art before writing the contrast
  test, and prefer a ground or an outline under the words to a veil over the picture.
- **Docs:** Deadnight `docs/research/calling-cards.md#the-box-the-maintainers-question`.
