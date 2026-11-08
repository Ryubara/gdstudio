---
areas: [godot-ui, tests]
---
# A capture that built its own router and overlay hid that the real menu was stale

2026-11-04

- **Saw:** Deadnight #1130's capture showed LEVEL UP 12 cards over a plate that said LEVEL 1. The capture built the
  router and `MenuPopups` itself, so it did not say whether a player sees it. In the real `Main` (loaded as a scene, a
  real sign-in, the account's profile read after the menu was up) the plate said LEVEL 4 under cards for levels 7 and 8,
  the wardrobe had 52 of 124 cells locked where level 12 leaves 39, and the shop and the stage read level 4 too.
- **Cause:** the menu read the profile file once, when it was built, and the start-up sign-in's read lands later; nothing
  told the menu the file changed. The wardrobe took its unlocks once at build, so even a level gained in a night kept the
  old locks.
- **Fix:** `ProfileUplink.adopt_and_tell` tells `ProfileFeed.shared.adopted`, `MainMenu` reads the file again when the XP
  differs, and `MenuShell.set_profile` re-locks the wardrobe (`CustomizeScreen.set_unlocks`). A test fails without it. Check
  for next time: a suspected fault seen in a capture that assembles its own parts is first run in the real scene, with a
  throwaway user folder.
- **Docs:** [A throwaway user folder for the real game](../engines/godot/throwaway-user-folder.md).
