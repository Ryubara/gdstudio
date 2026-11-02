---
areas: [godot-ui, blender]
---
# The menu soldier held the weapon with a copy of the hold code, and missed the grips

2026-11-02

- **Saw:** "hand placements on gun is not correct in main menu, why is that separated from the main hand placement
  logic?" (Deadnight #621): on the main menu the soldier held the lever rifle with the fists off the grip and the
  fore-end. Measured on main: the right palm 36.8 mm inside the weapon, the thumb tip 67.7 mm off it, the left index
  tip 63.5 mm off the fore-end.
- **Cause:** the menu's `MenuHero` (#424, #466) had copied the night's weapon setup (a mount on the hand bone, the kit's
  `HOLD_GUN`, a `WeaponHandsIK`) five hours before #507 solved a grip per model (`HandGrip`, `HandGripPose`) and wired
  it into `PlayerAnimation` only. #507's test builds the real player and no other view of the soldier, and the menu's
  tests only checked that a weapon node existed, so the copy kept the old fist. The copy also looked the weapon up by
  class, not by weapon, so the SMG showed the lever rifle and the pistol and flare gun were not on the menu at all.
- **Fix:** one builder, `HeldWeapon` (Deadnight `game/gameplay/player/held_weapon.gd`), that the night and the menu both
  call; `test_menu_grips.gd` compares the menu's weapon, grip, hold and hand place with the real player's for every
  weapon, measures the hands against each weapon with the night's limits, and fails when a menu file builds a hand
  pose itself.
- **General:** a second place that shows a held item (menu, wardrobe, lobby, replay) calls the code that holds it in the
  night, never a copy of its set-up; when you change how a thing is held, grep for every view of it and give each a
  test that measures the same contact as the night's test. A copy that "looks the same today" is a bug on the day the
  data it copied changes.
- **Docs:** [Hands on the weapon](../blender/weapons.md#hands-on-the-weapon),
  [What the maintainer caught](../research/maintainer-corrections.md).
