---
areas: [godot-ui, tests]
---
# A phone button that shows only sometimes was a hidden case in seven suites that listed the buttons

2026-11-05

- **Saw:** Deadnight #1285 made the Melee circle a contextual Strike button (like Interact, it shows only while a dead is
  in reach). The first full run of `tests/ui` and `tests/night` was red in suites the change never named: a cooldown test
  tapped a button that was not up (the first blow killed the dead, and the button went with it); the marker suite put
  Strike under every run; a box count expected one hidden button and found two; a list of "small" hit areas, the input
  matrix's touch row and the popup lane's "every hint is showing" all assumed the button was always there. After those,
  the pre-commit `gdlint` failed on a new public query (`TouchControls` was at the 20 public methods it allows), and a
  hint of 407 units ("TAP TO STRIKE") covered the Perks card of the 667 x 375 page at 1.25.
- **Cause:** a button that shows only in a context is a hidden state in every suite that lists, counts or presses the
  buttons, and each suite holds its own picture of "the buttons". The change was checked by its own suites first.
- **Fix:** before the first run, `grep -rn "TouchLayout.<ID>\|TouchHints.ORDER\|button_boxes"` over `game/tests`, and
  give the fixture a switch for the context (`TouchFixture.strike_up`) instead of editing each suite's picture; a test
  of a repeated tap keeps the button up by hand when the first blow takes the context away. Expose a new query as a
  property when the class is at the linter's limit of public methods. Check a hint's width on the smallest canvas
  (1536 x 864 with 96-unit insets) before choosing its words; run `uvx pre-commit run --all-files` before the long suites.
- **Docs:** [Touch controls](https://github.com/Ryubara/deadnight/blob/main/docs/design/touch-controls.md), Deadnight.
