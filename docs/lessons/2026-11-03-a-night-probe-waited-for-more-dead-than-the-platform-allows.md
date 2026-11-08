---
areas: [tests, general]
---
# A night probe waited for 64 dead on a platform whose ceiling is 40

2026-11-03

- **Saw:** a probe started with the autopilot (`alive=100`, `tough=300`) to read the HUD's draw calls "once 64 dead
  stand" printed nothing for ten minutes: the run went on to its 400 seconds and sat there, the process never ended
  (Deadnight #948).
- **Cause:** the crowd stops at the platform's ceiling, 40 dead (`alive_cap`), whatever `alive` asks for; the probe's wait
  was never met. The issue that asked for the measurement had counted 64 dead on another build.
- **Fix:** wait for the ceiling (`hudalive=40`), and give every wait in a probe an end (a night's seconds or a frame
  count), so a number that cannot be reached ends the run with a line saying so. Stopped the stray Godot by its process
  id, not by name.
- **Docs:** [Performance review](../engines/godot/performance-review.md#how-to-measure-it-counts-first).
