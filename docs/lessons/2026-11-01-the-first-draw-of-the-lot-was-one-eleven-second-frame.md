# The first draw of the lot was one eleven-second frame

2026-11-01

- **Saw:** in the web build, pressing Play showed a loading bar that did not move for 9 to 12 s: the page's frame delta
  was 11 s, with 79 GL programs linked in that one frame, and a second frame of 3.6 s for the enemies and weapons.
- **Cause:** the first bind of a shader makes its four variants at the engine's default specialisation (every light
  type, area lights, lightmaps), which takes 0.5 to 0.9 s each for the two colour programs; the lot has nine lit
  shaders and everything was drawn in one frame. A navigation bake had been blamed first; it took 0.5 s.
- **Fix:** hold the night's meshes out of the picture (`RenderingServer.instance_set_visible`) and bring them back one
  new kind of material per frame, stop the HUD's portrait viewport until they are in, and draw effects one at a time:
  the longest loading frame went from 9 to 11 s to 2 s and the bar moves; the total did not shrink, it is
  the sum of the lit shaders. A browser run fails when a frame links more than 12 programs.
- **Docs:** [First-use hitches](../godot/first-use-hitches.md).
