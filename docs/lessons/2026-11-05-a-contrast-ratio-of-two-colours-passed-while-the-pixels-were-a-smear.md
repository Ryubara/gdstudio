---
areas: [godot-ui, tests]
---
# A contrast ratio of two colours passed while the pixels were a smear

2026-11-05

- **Saw:** Deadnight #1189. Every test of the words on a plated player box passed (the ink against the seat's colour,
  5.6 to 14.9 to one), and in a night on a phone the level and the name were a dark smear on the card (the strongest
  pixel read 1.3 to 3.4 against 4.5; the median letter pixel 1.1 to 1.8: no contrast at all). The same word read 4.8 on
  one card and 6.5 on another over the same strip.
- **Cause:** the design check compared two colours; the eye gets those colours blended by how much of each pixel the
  strokes cover, and a stroke under a pixel wide never fully covers one. An outline of 3 units is a pixel on a phone, as
  wide as the stroke. Then the first pixel reading used the whole label's box as the ground, so the card above and
  below the words moved the number.
- **Fix:** read the pixels (`test_plate_words`): draw the place as it is, with the words clear and with the words in
  one flat colour, take the ground from the rows and columns the word covers, and report two numbers: the strongest
  pixel (the issue's) and the median pixel the letters mostly cover against the pixels beside it (0 is a smear). Give
  the words one ground (a strip of the seat's colour) rather than an outline, and a heavier face where a unit is under
  0.6 of a pixel. Check for next time: a contrast test of words that must be read on a phone reads pixels at the
  factor the screen runs at, and a number that depends on the card behind it, with the strip unchanged, is measuring
  the wrong ground.
- **Docs:** Deadnight `docs/research/plate-words-contrast.md`.
