---
areas: [tests, godot, gameplay]
---
# The async navigation map dropped the last of several door meshes, and the dead stood still

2026-11-03

- **Saw:** Deadnight's `ci` went red on `main` (#733): `test_smallmap_windows` tore 7 of 12 windows in 5400 ticks, and
  `test_smallmap_bot_night` (#736) failed about one run in two on a developer machine, round 1 never closing with four
  dead standing still. A merged change was not the cause (the first red commit touched bot errands only); the same suite
  alone was deterministic (the same tick every run, also under four parallel runs).
- **Cause:** both tests sold every link in one loop, which swaps the saved mesh into the region three times in one go.
  With `navigation/world/map_use_async_iterations` on (the default) the map synchronises on a worker thread, and in some
  runs it ended on a mesh that lacked the last doors: the final iteration id was 7 where a good run ended on 8 or 9, and
  `map_force_update` did not move it. The dead's paths ended 3 m short of the players (the side room and the stairs cut
  off), so they stood.
- **Fix:** the night's world turns `map_set_use_async_iterations(map, false)` off for its map, so the physics step
  takes a mesh in and the server's dead path the same on every machine. Six runs of the suite passed after, against
  about half failing before; a test asserts the setting and that a path from each window reaches the hall.
- **Check:** a sim that must be deterministic must not read a navigation map that a thread updates; when a
  stand-still dead is the symptom, print each dead one's `map_get_path` end against its target before blaming the AI.
- **Docs:** [Navigation in tests](../engines/godot/navigation-in-tests.md).
