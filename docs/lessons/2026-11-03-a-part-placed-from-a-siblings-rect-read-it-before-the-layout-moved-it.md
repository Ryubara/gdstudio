---
areas: [godot-ui]
---
# A part placed from a sibling's rectangle read it before the layout had moved it

2026-11-03

- **Saw:** the perk badges stood beside the health card on desktop, but with the touch layout on (the slot strip moves
  under the card, so the card moves up) they sat 70 units too low: a test that the badges' bottom equals the card's
  bottom failed by 70 (1044 against 973), no error.
- **Cause:** the badges were placed in the card's `item_rect_changed`. The card sits in a bottom-anchored column that is
  itself placed after its children, so the signal fires with the card's old global position.
- **Fix:** connect the card's, the column's and the badges' own `item_rect_changed` to a function that queues one
  deferred placement (a flag so it runs once per layout pass), and place from the rectangles then. Test it by flipping
  the layout and measuring the rectangles after two idle frames.
- **Docs:** [UI controls](../engines/godot/ui-controls.md#a-part-placed-from-another-parts-rectangle).
