---
areas: [web, godot]
---
# The web build's night took 82 to 107 s to load in CI and 20 s on a desktop

2026-11-02

- **Saw:** Deadnight's web smoke measured 82 to 107 s from Play to a running night (limit 150 s, main went red on a
  slow runner); the same build took 20 s with a GPU and 30 s in SwiftShader on a fast PC.
- **Cause:** (1) The warm-up behind the loading screen draws the level and a stage of every thing for about 100
  frames at the window's size; a renderer on the CPU pays for every pixel (0.1 to 0.3 s a frame at 1280 x 720; the
  same run at 640 x 360 took half). (2) The effects were replayed in four light conditions, three of them linking 0
  programs. (3) 240 sounds were decoded to samples by a GDScript loop over every sample behind the bar. (4) With a GPU
  every lit shader costs a default-specialisation pair of programs (0.6 to 1.0 s each) that nothing draws with, and
  seven materials set `specular_mode = DISABLED`, a shader of their own for a look `metallic_specular = 0` gives.
- **Fix:** the warm-up draws into a 160 x 90 `SubViewport` of the same world with the window's 3D off (programs do
  not depend on the picture's size; the window draws the night once at the end); effects replayed once; the audio
  service loads sounds in the background while a menu is up; the seven materials use `metallic_specular = 0`. 30.5 s
  to 7.5 s in SwiftShader, 20.4 s to 16.0 s with a GPU, the same 207 programs, none linked while playing.
- **Docs:** [First-use hitches](../engines/godot/first-use-hitches.md#a-warm-up-on-the-cpu-pays-for-every-pixel).
