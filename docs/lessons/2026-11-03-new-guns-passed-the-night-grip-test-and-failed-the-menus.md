---
areas: [tests, blender]
---
# Three new guns' left hands passed the night's grip test and floated 0.1 mm past the menu's limit

2026-11-03

- **Saw:** Deadnight #793 (six firearms) failed CI on `test_menu_grips.gd`: `m249 L pinky_tip 5.1 mm off the weapon` and
  `pump_870 L palm 5.2 mm off the weapon` (the limit `HandContact.MAX_FLOAT` is 5 mm), for every top of both Soldiers.
  `test_hand_grips.gd` (the night) and every suite I ran locally passed.
- **Cause:** the grips came with the model batch (#796) and were measured in the night's rig; the menu Soldier is skinned
  a little differently and has its own measure, in a folder (`tests/ui`) I had not run, because the change was
  "weapons and rules".
- **Fix:** moved each left hand 2 mm up its weapon (`left_hand` origin in `grips/<model>.tres`) and ran both tests.
  A new held model runs `tests/ui/test_menu_grips.gd` and `tests/player/test_hand_grips.gd` before the pull request.
- **Check next time:** a new weapon model touches four views of one hold (night, menu, other players, the bench): run
  the suite folder of each view, not the folders of the files edited.
- **Docs:** none yet.
