---
areas: [godot, web]
---
# A backdrop colour passed as linear drew ten times too dark

2026-11-03

- **Saw:** Deadnight's unshaded backdrop shader, fed the environment's fog colour through `srgb_to_linear()`, drew
  `(0, 0, 15)` where the renderer's own fog of the same colour drew `(31, 45, 90)`. An earlier try that wrote the
  spatial shader's `FOG` output instead drew black at alpha 0 and far too bright at alpha 1.
- **Cause:** the Compatibility renderer takes colours as they are (it behaves as if it lights in sRGB space): a uniform
  converted to linear first is treated as a much darker sRGB value.
- **Fix:** pass the environment's and lights' colours unconverted, times their energies, as plain `vec3` uniforms,
  and make the far models unshaded with their own lighting and haze; then compare one pixel with the renderer's own fog.
- **Docs:** [A backdrop past the playable bounds](../engines/godot/compat-lighting.md#a-backdrop-past-the-playable-bounds).
