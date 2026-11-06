---
areas: [godot-ui]
---
# A card measured its height from the container before the layout had used its new width

2026-11-05

- **Saw:** a placement search (Deadnight #1299) tried a card at three widths and took the first place that missed every
  box, and the drawn card still stood over a touch button by 10 units: it had measured 163 high at the narrow width
  and was 175 once drawn. At another width the card stayed 316 wide where 190 was asked for.
- **Cause:** `get_combined_minimum_size()` of a container read straight after its child's `custom_minimum_size` was
  changed answers for the width the label last had, and a wrapped `Label`'s lines are laid out at its size, which only
  the next layout sets; `font.get_multiline_string_size` is also 4 units a line shorter than the label's own line
  height. A control that no container holds keeps the size it had until `reset_size()`.
- **Fix:** the card measures itself from its parts (`HudChallengeCard.size_at`: the padding, the row, the lines the
  words break into at the width times `get_line_height()`, the holes) and keeps its size at its least
  (`minimum_size_changed` calls `reset_size()`); the search takes the laid-out height for the width the card has now
  (`HudChallenge.laid_size`) and the estimate for the others, and looks again each frame. A test makes the card each
  width, waits two frames and checks the measure is never under the laid-out height. A real page (Chrome as a phone)
  broke what the headless run had agreed on: the same words took a third line there, so the card was run on the page
  too (`tools/web_smoke/challenge_card_phone.py`).
- **Docs:** [UI controls](../godot/ui-controls.md#a-card-that-looks-for-free-ground).
