---
areas: [web, tests]
---
# Two phone profile runs of one setup differed ten times

2026-11-03

- **Saw:** the web build on a phone-sized Chrome, same build and same pixel ratio, ran at a median of 28.8 ms in one
  run and 309 ms in the next; ratio 2 looked slower than ratio 3 (Deadnight #689). A CPU-throttled run with a fast GPU
  showed no change at all from a change that more than halved a fill-bound frame.
- **Cause:** the machine is shared, so separate runs got different shares of it; and a CPU throttle on a fast GPU hides
  fill cost, so it could not see a pixel change whatever it did.
- **Fix:** one page switches between the ways of drawing every 30 s (interleaved arms, the first seconds after each
  switch dropped), so every arm sees the same minutes; fill cost is measured with SwiftShader, processor cost with the
  throttle, and each result is read as a ratio, never as a phone's frame rate.
- **Docs:** [The web build on a phone](../engines/godot/web-phone-frames.md); Deadnight `docs/research/phone-frames.md`.
  Check: a before/after on a shared machine is interleaved in one run, and the stand-in is chosen for the cost the
  change touches.
