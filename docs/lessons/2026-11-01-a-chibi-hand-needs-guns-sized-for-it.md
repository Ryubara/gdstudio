# A chibi hand needs guns sized for it

2026-11-01

- **Saw:** the maintainer: "the player's hands are too big for some guns"; the revolver's grip was 0.94 of the fingers
  under the trigger finger, its guard 0.67 of the finger's thickness.
- **Cause:** the size rule scaled weapons to the body (real x 0.8 x 1.1), but the kit Soldier's hand is 2.3-3 times
  real; the kit draws its guns about 1.33 times real for it.
- **Fix:** rule factor 1.3, a grip-fit size factor for guns whose grip is short of the fingers, a deeper guard where
  the finger did not fit; measure grip, guard and fore-end against the hand before solving.
- **Docs:** [Blender weapons](../blender/weapons.md#hands-on-the-weapon).
