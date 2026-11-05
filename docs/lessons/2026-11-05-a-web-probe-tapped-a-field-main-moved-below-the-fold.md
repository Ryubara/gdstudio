---
areas: [web, input, godot-ui]
---
# A web probe tapped a field that a merge had moved below the fold

2026-11-05

- **Saw:** after Deadnight main brought #1232 (server browser) and #1225 (phone layout) into #1200, the `web` job failed
  in `phone_keyboard.py`: a tap on the code field opened no keypad, and the probe saw only four buttons.
- **Cause:** not the game. The server browser's note and button came above the code field, which on a 390 px page now
  rests at 101 % of the height (below the fold of a card that scrolls). The probe tapped the box the game reported, a
  point off the page. A second probe step then tapped `(40, 40)` to "tap nothing", which the phone layout made the menu's
  Play tab. Swiping the card up with a finger, from the scroll area's margin (a drag that starts on a button is the
  button's), put the field in reach and the keypad opened.
- **Fix:** `scroll_into_view` (a touch drag) before tapping a field the screen may have pushed down, and one named
  `EMPTY_SPOT` for taps that must hit nothing; in `phone_keyboard.py` and `phone_join.py`. No check was loosened.
- **Check for next time:** a probe that taps a reported box checks first that the box is on the page, and scrolls as a
  player would when it is not; a "tap nothing" is a spot the screenshot shows empty on every screen the probe visits,
  never a corner. After merging main, export the web build from the merged head and run the web job's probes on it
  before pushing (a build exported earlier showed the field at 204 px and passed). Documented in the game's
  `docs/research/phone-keyboard.md`.
