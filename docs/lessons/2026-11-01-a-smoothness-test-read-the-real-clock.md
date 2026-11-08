---
areas: [tests, godot]
---
# A smoothness test read the real clock and failed on busy machines

2026-11-01

- **Saw:** Deadnight's side-on smoothness test (from #352) failed main's CI with 11.7 px against a 2 px limit and with
  about 55 px on a busy local machine, and passed on quiet ones. Every pull request went red.
- **Cause:** in the test's own process each frame's length and `Engine.get_physics_interpolation_fraction()` come from
  the real clock, and a script cannot set either. The camera spring samples the body once a frame and trails it by half
  a frame, so uneven frames move the body on screen.
- **Fix (Deadnight #362):** the test starts a child Godot with `--headless --fixed-fps N` on a probe scene
  (`OS.execute(OS.get_executable_path(), ...)`) and reads its one output line, at 100, 144 and 165 fps; two control
  cases (body not interpolated, rig blended twice) must show more than 5 px, so the measure is proven against the faults
  it guards. The limit is unchanged.
- **Check:** anything measured per drawn frame runs at a fixed frame length, never at the machine's.
- **Docs:** [Physics interpolation](../engines/godot/physics-interpolation.md).
