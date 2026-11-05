---
areas: [godot-ui]
---
# A row saving was sized from the row and missed the card by four units

2026-11-05

- **Saw:** a whole rule title overflowed the narrowest phone's card by 20 units (`test_ui_fit`); a first fix that took 16
  units from the row's gaps still left the card 4 units over the canvas.
- **Cause:** the saving was sized against the widest row (820 units), not against the card's whole width budget: row, the
  scroll's 48 unit bar, the card's 80 units of padding and the screen's side margins. The test showed the 4 units at once.
- **Fix:** write the budget as a sum first (canvas less margins less card padding less scroll bar against the row's
  minimum), take the saving from the cheapest line (here the side margins, which the top and bottom already had) and run
  the fit suite for the page before committing. Never move the fault out of the test's pages instead.
- **Docs:** Deadnight `docs/research/phone-page-scale.md` (the solo Play screen's budget).
