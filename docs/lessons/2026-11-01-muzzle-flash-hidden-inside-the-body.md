---
areas: [godot, tests]
---
# A muzzle flash that never showed

2026-11-01

- **Saw:** the flash fired (node visible, shader fine in a test scene) but no capture showed it.
- **Cause:** it was placed at the server's muzzle, an offset from the body that the over-the-shoulder camera sees
  behind the helmet; the depth test hid it.
- **Fix:** hang the effect on the weapon model's own `Muzzle` node; a weapon with no model flashes 0.6 m down the
  barrel.
- **Docs:** [Shot feedback](../godot/shot-feedback.md).
