---
areas: [godot, web]
---
# Shader math that is undefined in GLSL ES 3.0 passed on a desktop GPU

2026-11-01

- **Saw:** nothing on desktop; a review found `pow(negative, 2.0)`, `smoothstep` with reversed edges and `sin` hashes.
- **Cause:** desktop drivers happen to return something sensible; WebGL2 drivers may give NaN or stripes.
- **Fix:** write `d * d` instead of `pow(x, 2.0)`, keep `smoothstep` edges ordered (clamp the width with `max`), and use
  one shared sine-free hash in a `.gdshaderinc` included with `#include`. Check in a real browser export.
- **Docs:** [Compatibility lighting](../engines/godot/compat-lighting.md); Deadnight `docs/research/main-menu.md`.
