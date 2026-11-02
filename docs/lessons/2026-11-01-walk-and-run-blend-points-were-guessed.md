---
areas: [gameplay, tools]
---
# The dead's feet slid because the walk and run blend points were guessed

2026-11-01

- **Saw:** after Deadnight's speed rework (up to 6.25 m/s), fast zombies slid across the ground; a half walk, half
  run blend slid too.
- **Cause:** the blend points were 1.0 and 3.0 m/s, guesses; the clips' own ground speeds measure 0.97 (Walk) and
  4.4 m/s (Run). Above the top point the clip played at its authored rate. Blending two looping clips of different
  length that are out of phase covers less ground than the blend position says.
- **Fix:** measure each clip's planted-foot speed, put the blend points there, put the move state behind an
  `AnimationNodeTimeScale` set to ground speed over the gait's own speed (clamped 0.5-1.6), and cross over from walk
  to run over a short band, solving the rate so the blend covers the target speed.
- **Docs:** [Crowds](../godot/crowds.md#gait-follows-speed).
