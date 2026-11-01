# A grenade in the gun hold lay on its side

2026-11-01

- **Saw:** a grenade turned 180 degrees about X stood upright in the Blender contact sheet, but lay on its side in the
  Soldier's hand in Godot.
- **Cause:** the Blender preview turned it against the kit Shotgun's copy in the character file, which carries its own
  node transform; Godot's `HOLD_GUN` already divides that out, so the same turn means something else there.
- **Fix:** render eight turns of `HOLD_GUN` on the held pose in Godot and keep the one that reads (90 degrees about X).
- **Docs:** [Blender weapons](../blender/weapons.md#axes-origin-and-the-hold).
