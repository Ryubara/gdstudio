---
areas: [gameplay, blender]
---
# A bigger lamp range pushed a ground tile over the light cap

2026-11-01

- **Saw:** after widening the lamps to 14 m for bigger pools, a field ground tile was reached by 11 lights; the
  renderer lights a mesh with at most 8, so the rest would be dropped (and pop on and off as circuits switch).
- **Cause:** the cap is per mesh, and one 24 m tile touches every lamp, the screen glow and the stand's lights within
  their range; raising the range raises the count.
- **Fix:** keep the range, draw the pool as an additive quad, tile the field's ground at 16 m, and a test that counts the
  lights reaching every CSG box with every circuit on.
- **Docs:** [Compatibility lighting](../engines/godot/compat-lighting.md#lamps-in-a-game-what-looks-like-light-and-what-is-light).
