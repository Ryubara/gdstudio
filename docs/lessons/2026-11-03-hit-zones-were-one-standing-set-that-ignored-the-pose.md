---
areas: [gameplay, tests]
---
# Hit zones were one standing set for every pose, and no test shot at the mesh

2026-11-03

- **Saw:** "Bullets landing on Zombie crawlers is a bit hit or miss especially when hitting their forehead" (Deadnight
  #694). A ray grid over the crawler's skinned mesh: 22% of the shots that touched it registered, 1% of those at its head
  counted as head, 0 of 12 forehead shots through a combat server were headshots. A walker's: 56 to 70% registered.
- **Cause:** analytic hit shapes (spheres and capsules, so the server can rewind them) were one upright template placed
  from the feet and only scaled, while the view plays other clips by mode (crawl, punch, hit reaction). The crawler's head
  zone floated 0.97 m up, behind a half-metre head 0.5 m up. The tests fired rays at the shapes themselves, and aim tests
  aimed at points computed from the same numbers, so shapes and mesh were never compared.
- **Fix:** fit the shapes to the skinned mesh per look and pose (a tool skins the mesh on the CPU in each clip and fits
  capsules to the bone pieces over the clip), send the pose with the target, and keep a test that fires a ray grid at the
  skinned mesh in each pose through the server's own trace and asserts the rates (it fails on `main`).
- **Docs:** Deadnight `docs/research/hit-zones.md`. Check: whenever a hit, grab or occlusion shape is separate from the
  mesh, a test fires rays at the visible mesh in every pose the animation puts it in and reports before and after rates;
  a shape that is only tested against itself is not tested.
