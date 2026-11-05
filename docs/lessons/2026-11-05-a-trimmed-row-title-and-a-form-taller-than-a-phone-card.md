---
areas: [godot-ui, web]
---
# A rule title cut to "Break between ro..." and a code field under a phone's fold

2026-11-05

- **Saw:** on a phone page (844 x 390 CSS px, a 1168 x 540 canvas) the lobby's row title read "Break between ro..." while
  the solo Play screen showed the whole label, and Play together ended on "Create a night" with the code field, Join and
  Back below the fold, a scrollbar the only sign. Every earlier capture was a window of 844 x 390, so neither showed.
- **Cause:** a `Label` that trims (`OVERRUN_TRIM_ELLIPSIS`) asks a container for no width of its own, so a column's
  least width (`UIRow`: 220 units) wins, and a card that is only as wide as its rows' minimums never gives the column
  more; the Play screen's card was wider, so it had slack. The Play together card held five 79 unit controls and a
  title in a 436 unit view: no ordering of one column fits, and a fold cannot be made plain at that size.
- **Fix:** let the title keep its whole text (`UIRow.show_whole_title`, so the column grows to it) and test it with the
  label's own measure (`UIRow.title_cut`, text width over the label's width); on a phone's canvas drop what is not
  needed (overline, note, an empty status line) and put the choices two to a row in a `GridContainer`, then assert
  every control lies inside the scroll's view on each real page (`test_phone_fold`). Add a section to the web probe so a
  capture of the lobby and Play together exists at ratio 2 and 3.
- **Docs:** the game's `docs/research/phone-page-scale.md` ("Play together and the lobby's rules"); the web probe is
  `tools/web_smoke/phone_layout.py` (`--section together,lobby`).
