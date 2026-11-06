---
areas: [gameplay, godot, tests]
---
# A Roam bot stood for good in a corner: a dodge ended on a piece of mesh only the dead walk

2026-11-06

- **Saw:** the nightly soak's `idle under Roam over 8 s` samples at `(-15.4, 32.4)` (goals `(-24.3, 0.4, 32.1)` and
  `(-36.0, 0.4, 36.6)`, `path: 4` = `UNREACHABLE`, `stuck` false), the corner of a fence and a wall, 0.4 m from each.
  A bot and a person set down there made no headway, and the bot "from the mesh" walked the same goals fine. The
  breaker post's fix (#1335) did not touch it; the guess "the same hole" was wrong.
- **Cause:** two parts, and no push or jump was needed. (1) `BotSteering._on_mesh` took the end of a reflex heading for
  mesh when `NavigationServer3D.map_get_closest_point` found a point within 0.45 m, and that query ignores navigation
  layers: a scrap that only the dead walk (`NavLayers.GAP`, put there by #1051) counted. The step a bot makes out of
  the way of a person (`BotLegs._give_way`, 0.6 s at a run) ends 2.5 m on, on the scrap. (2) A walking path starts on the
  nearest *walking* polygon, which the server picks by distance, so from the corner it lies across the wall: the path
  begins behind the wall, the bot is walked into it, the stuck ladder only drops goals, and the next goal starts the same
  way. Found by printing 12 s of trail for any bot in the corner in soak nights (one night of 6 had it, round 8),
  then reproduced by a person walking at a bot at the stand (16.8 s in the corner on
  `main`).
- **Fix:** a reflex step ends only on walking ground (`BotLevel.on_walking_ground`: the owner region of the nearest mesh
  point has `NavLayers.WALK`), and `BotPath._start` starts a path at the nearest walking ground that is open to the bot
  when the nearest mesh point is not walking ground or a wall is on the line to it. `test_bot_west_corner.gd`: a bot set
  down in the corner walks 3 m out in 5 s, and is not stepped in by a person.
- **Check for next time:** a "nearest point on the mesh" query is layer-blind: when the mesh has regions on layers (the
  dead's gaps, scraps, roofs), ask what owns the point before calling it ground for a person. A sample whose spot lies
  inside the mesh's margin of a wall is a body off the mesh: find the step that put it there (print its trail) before
  guessing at the goal. A test of "set down at the spot" proves the exit, never the entry: it needs a second test that
  reproduces the approach, and each must fail on `main`.
- **Docs:** Deadnight's `docs/research/bots.md` ("A Roam bot in the west midway's corner (#1339)").
