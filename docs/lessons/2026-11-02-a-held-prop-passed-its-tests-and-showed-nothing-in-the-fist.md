---
areas: [gameplay, godot]
---
# A grenade in the hand passed every test and was invisible in the capture

2026-11-02

- **Saw:** Deadnight #285: the grenade's hold test passed (node visible, 5 to 25 cm from the hand bone, length on the
  rule), and the capture sheet's side view showed an empty fist, before and after the change.
- **Cause:** a prop smaller than the chibi's fist hides inside it from the side; "visible" and "near the hand" say
  nothing about whether a camera sees it. The sheet had the same four views as the guns, none close.
- **Fix:** give a small held prop its own close views (the hand beside, from the front) in the capture sheet, look at
  them before reporting, and size it by a declared exception (`size_factor` 2.2 in `holds/grenade.tres`), then re-solve
  the grip (`tests/art/solve_grips.gd --only grenade`).
- **Also:** adding the model code pushed `player_animation.gd` over gdlint's 1000-line limit at commit time; drop dead
  fallbacks (the placeholder shell) instead of growing the file, and keep commit titles to 72 characters (a staged
  commit that failed its hook is not made, so a following `git merge` fast-forwards past your staged changes).
- **Docs:** Deadnight `docs/design/weapon-hold.md`, "The grenade in the hand".
