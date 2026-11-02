# A view that rereads saved state on "setting changed" erased the unsaved outfit

2026-11-02

- **Saw:** the maintainer: outfits reset when changing the character and then the showcase weapon, and when clicking
  out of the loadout to another tab (Deadnight #489).
- **Cause:** the showcase-weapon click wrote `loadout/weapon` to the settings on every click; `Settings.changed` made
  the menu stage (`MenuStageView.reload_look`) redress the soldier from the saved look, erasing the outfit not yet
  saved; leaving the tab wrote nothing, since only a footer Save button saved. The tests (#466) called
  `wardrobe.apply_preset` and `wardrobe.save()` directly, never one choice then another, a tab change and a reload,
  and one test pinned "leaving unsaved puts the saved look back" as intended.
- **Fix:** hold the screen's choices in one draft while it is open, preview the draft on the stage, and commit once
  when the player leaves (Deadnight #493).
- **Check:** any panel with more than one choice has a test: change A, then B, then tab away and back, then reload
  from the file, counting writes (0 while open, 1 on leaving). Held choices never go through a setting that other
  views react to.
- **Docs:** [What the maintainer caught](../research/maintainer-corrections.md).
