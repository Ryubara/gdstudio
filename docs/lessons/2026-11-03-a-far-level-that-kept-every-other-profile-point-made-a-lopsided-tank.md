---
areas: [blender]
---
# A far level that kept every other profile point made a lopsided tank

2026-11-03

- **Saw:** the far level of Deadnight's freeze gun had a tank tapered to a cone at the front and cut square at the
  back, though the held level's two rounded ends were alike.
- **Cause:** the far level kept every other inner point of the turned profile (as `weaponlib.Builder.lathe` does);
  on a six-point profile that keeps one shoulder of the front end and the flat side, and drops the back shoulder.
- **Fix:** a turned part with rounded ends takes a far profile of its own, drawn by hand from the same outline
  (`revolve_x(..., far=[...])` in Deadnight's `tools/blender/weapon_specs/_revolve.py`); look at the far level in a
  turntable beside the near one.
- **Docs:** [Weapons: building by script](../blender/weapons.md#building-by-script).
