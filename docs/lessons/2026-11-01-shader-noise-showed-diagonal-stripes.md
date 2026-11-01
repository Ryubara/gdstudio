# Shader noise showed diagonal stripes

2026-11-01

- **Saw:** film grain and a starfield showed diagonal bands; edges flickered differently between GPUs.
- **Cause:** the `fract(sin(dot(...)) * 43758.5)` hash loses precision on large arguments; and `smoothstep` with
  reversed edges (`smoothstep(1.0, 0.0, x)`) is undefined in GLSL, so drivers disagree.
- **Fix:** a sine-free integer-style hash; write `1.0 - smoothstep(0.0, 1.0, x)` instead of reversed edges.
- **Docs:** Deadnight `docs/research/main-menu.md`.
