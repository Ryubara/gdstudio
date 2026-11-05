---
areas: [godot-ui, tests]
---
# A scroll card passed every fit test and showed no item to choose from

2026-11-05

- **Saw:** the Loadout card on a phone opened on a sliver of the "Weapon" label cut through its letters, and nothing
  to choose until the player scrolled an area 33 units (23 CSS px) tall; at 844 x 390 it was 99 units and still no
  item. `test_ui_fit`, `test_phone_floor` and the web probe's text and tap floors were green on all of it.
- **Cause:** a fit test asks whether the content stays inside the card, and a scroll area passes that for any height,
  even a sliver. The card's own chrome (the theme's 32 and 24 unit margins, two rows of tabs, a detail line, a footer
  row under it) took 339 of the 372 units a phone leaves a tab, and the first thing in the page was the weapon row.
  The other tabs were measured too (Play 372, Shop 233, Challenges 217, More 372 units of view): only Loadout lost it.
- **Fix:** the scroll view is what is measured now: `test_menu_header` counts the items that lie whole inside the view
  on opening (and a label cut at its top, and a card that opened scrolled), at six phone pages; the web probe
  publishes `loadout_items`. The card was cut to fit it: margins 8 and 6, the tabs one row, the footer row inside the
  card, the weapon row at the end of the page. A focus on the weapon row below the fold had scrolled the card to its
  foot (`follow_focus`), so a panel's first focus is something in view. Deadnight #1271.
- **Check for next time:** for a scroll area, assert what is in the view after the tab opens and after the first key
  press into it (whole items, nothing cut at the top, scroll still 0), at the smallest page; a height budget (what the
  chrome takes, what is left) belongs in the pull request.
- **Docs:** Deadnight `docs/research/phone-page-scale.md` (the tab bar and the Loadout card on the narrowest page).
