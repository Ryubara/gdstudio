---
areas: [blender, tests]
---
# A tank meant to show over a wall was sized before the sight line was worked out

2026-11-03

- **Saw:** Deadnight's generator (#853) had to read from the yard's gate over its cage's 3.0 m walls. The first build
  put the day tank's axis at 3.45 m; the gate capture showed a red sliver over the wall and a tiny lamp, not a tank.
- **Cause:** the heights were picked by eye in the model sheet, where nothing hides anything. From the shoulder camera
  (about 2.2 m up, 19 m off) the line over a 3.0 m wall is at 3.1 m where the generator stands, so half the tank was
  under it.
- **Fix:** work the sight line first (camera height, wall height and both distances), then put the whole part above it
  with some margin: the tank's belly at 3.18 m (axis 3.68), the running light at 4.68 m, the stack's lip at 5.3 m.
  Check it in a capture from the player's camera at the spot the issue names, not in the sheet.
- **Docs:** Deadnight `docs/design/style.md` (the generator set, under the drive-in props).
