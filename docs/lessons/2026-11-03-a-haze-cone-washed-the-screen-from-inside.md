---
areas: [godot, web]
---
# A lamp's haze cone washed the screen when the camera walked into it

2026-11-03

- **Saw:** in a corridor of ceiling lamps, the shoulder camera inside a lamp's additive haze cone turned the frame
  orange from edge to edge (Deadnight #636).
- **Cause:** the cone's shader fades a face as it turns edge-on to the eye; from inside, every face of the cone faces the
  camera, so all of it was drawn at full strength, added up front and back.
- **Fix:** fade the haze by view depth, `soft *= smoothstep(0.2 * near_fade, near_fade, -VERTEX.z)` (2 m), as a uniform
  that defaults to off so the other users of the shader are unchanged.
- **Docs:** [Compatibility lighting](../engines/godot/compat-lighting.md#light-cards-indoors-moon-shafts-door-glow-chalk).
