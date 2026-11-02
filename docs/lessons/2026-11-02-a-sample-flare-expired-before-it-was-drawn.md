---
areas: [web, godot]
---
# The first flare shot hitched the browser although the warm-up replayed a flare

2026-11-02

- **Saw:** in Chrome the first flare shot of a night linked 10 GL programs and had a 1.8 s frame (after a 0.2 to 0.33 s
  one), and a flare thrown after the first one's fire had burned out linked 8 more; the warm-up already replayed the
  flare's events and its draw ledger said nothing was missing.
- **Cause:** the flare's fire is a `GPUParticles3D`. The warm-up's sample fire was made to live 0.2 s and counts its age
  in frame deltas, which are seconds long while the warm-up builds programs, so it was freed before its first draw; and
  the warm-up's pins and the draw ledger only know `MeshInstance3D`s, so the particle system's process material and
  quad material were never kept or listed (a shader goes with the last material that uses it).
- **Fix:** the sample fire lives until the warm-up frees it by hand after three frames, the pins and the ledger cover
  particle systems (process material and each draw pass), and a browser probe fires the flare three times
  (`tools/web_smoke/flare_first.py`): 10, 0 and 8 programs before, 0, 0 and 0 after.
- **Check:** a sample effect in a warm-up never expires on its own; a ledger or a pin list that walks `MeshInstance3D`
  walks `GPUParticles3D` too; count programs linked after the first and the later uses of every effect in Chrome.
- **Docs:** [First-use hitches](../godot/first-use-hitches.md#particle-systems-two-programs-of-their-own-and-a-sample-that-expires).
