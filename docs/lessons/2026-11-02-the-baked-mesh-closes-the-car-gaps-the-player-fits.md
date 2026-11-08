---
areas: [gameplay, tests]
---
# The test crossed car gaps the mesh had closed

2026-11-02

- **Saw:** the scenario "every car gap is crossed" (Deadnight #226) took gaps from the cars' positions, put a bot 3.5 m
  either side and found it arrived with its closest approach to the gap still 3.5 m: it had walked round. Of about 60
  pairs of neighbouring cars the mesh passes four; the rest are a 12 to 34 m detour.
- **Cause:** the walking mesh is baked for a 0.5 m agent (the player is 0.35 m), and a 1.8 m gap loses 1 m to the
  erosion and some to the bake's cell size. The design page's "gaps between cars 1.8 m" is true of the walls, not of the
  mesh the zombies and the bots follow.
- **Fix:** pick the gaps by asking the mesh (a path across of about the straight length) and assert the closest approach
  to the middle, so a test that "crosses a gap" goes through it. Bots lag behind a person who cuts through the cars;
  say so in the research page instead of tuning it away.
- **Docs:** [Navigation in tests](../engines/godot/navigation-in-tests.md); Deadnight `docs/research/bots.md` (Built in
  phase 2).
