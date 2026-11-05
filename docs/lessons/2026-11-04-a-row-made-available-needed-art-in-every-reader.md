---
areas: [godot-ui, tests]
---
# A row made available needed art in every place that reads the table

2026-11-04

- **Saw:** Deadnight #1070 flipped 24 rows of the ladder's table (`unlocks.json`: the calling cards, the emblems, the tier
  cards) from `available: false` to `true` because their art was drawn. After a clean local run of the suites it
  could think of, CI went red on `test_popup_thumbnails`: #1147 had merged meanwhile, and the unlock popup card now takes
  its picture and name from `LadderItem` and has a test over every available row, which found four rows with no art.
- **Cause:** `available` is a promise to every reader of the table (the popup, the night report's "next", the voice
  lines, the wardrobe), not a flag for one screen; the change was made for the screens being built and checked against
  the readers that existed in the checkout, and main had gained a reader since the last merge.
- **Fix:** `LadderItem` and `PopupCard` learned the plate (`PlateCatalog` art and names, one source). Check for next
  time: before flipping a row or adding a kind of row, `grep` for every reader of the table (`LadderUnlocks`,
  `LadderItem`, `unlocks.json`) and run their suites; run `gds merge-main` and the whole UI folder once more
  right before opening the pull request, not only the suites that seem related.
- **Docs:** Deadnight `docs/research/calling-cards.md`.
