---
areas: [blender, gameplay]
---
# A chibi hand needs guns sized for it

2026-11-01

- **Saw:** the maintainer pointed out that the hands were too big for some guns; the revolver's grip was 0.94 of the
  fingers under the trigger finger, its guard 0.67 of the finger's thickness.
- **Cause:** the size rule scaled weapons to the body (real x 0.8 x 1.1), but the kit Soldier's hand is 2.3-3 times
  real; the kit draws its guns about 1.33 times real for it.
- **Fix:** rule factor 1.3, a grip-fit size factor for guns whose grip is short of the fingers, a deeper guard where
  the finger did not fit; measure grip, guard and fore-end against the hand before solving.
- **Earlier case (Deadnight #376):** the revolver and flare gun at the old size rule (0.88 x real length) vanished
  into the fist, only the barrel showing. Check every held item in a hold render before writing its hold, allow a
  size exception for one-handed guns (like the repair hammer, about 1.6x), and compare the catalogue's ids with
  the weapon model folders at the start of a weapon task (every id has its own model).
- **Docs:** [Blender weapons](../blender/weapons.md#hands-on-the-weapon).
