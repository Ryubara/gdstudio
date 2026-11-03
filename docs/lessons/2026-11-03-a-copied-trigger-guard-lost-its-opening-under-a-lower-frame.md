---
areas: [blender]
---
# A copied trigger guard lost its opening under a lower frame

2026-11-03

- **Saw:** the MP5 and M4A1 took the Tommy gun's guard, trigger and sockets unchanged, yet `measure_weapon_fit.gd`
  gave their guard 0.86 and 0.83 of the Soldier's finger against the Tommy's 0.95 (Deadnight #795).
- **Cause:** the guard's opening is measured from the trigger's front up to the first surface above it and down to the
  guard; their lower receivers hung 5-7 mm below the Tommy's receiver (-0.025 and -0.027 against -0.02).
- **Fix:** raise the lower receiver's bottom to the donor's -0.02: both came to 0.95. A copied guard keeps its fit
  only with the frame above it at the donor's height; measure the fit after the first build, before solving grips.
- **Docs:** [Weapons, hands on the weapon](../blender/weapons.md#hands-on-the-weapon).
