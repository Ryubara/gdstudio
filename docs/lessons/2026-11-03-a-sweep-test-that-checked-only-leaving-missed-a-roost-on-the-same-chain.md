---
areas: [gameplay, tests]
---
# A sweep test that checked only for leaving the map missed a roost on the same chain

2026-11-03

- **Saw:** after Deadnight #845 raised the plaza's walls, its sweep test passed: no chain of hops left the plaza. The
  same chains (a crate or a stack of tyres, then a container, the dumpster, the machine, the wreck) still stood the body
  on the junk at the end wall, and on the container's back edge, against the wall, ten dead in 40 s landed no blow
  (#855).
- **Cause:** the test asserted one kind of failure, "past a wall", and treated every standing place on the way as
  harmless. A place over the body's reach is reached only through a step, and a top against a wall is out of the dead's
  swing on its far side: a roost is the same chain stopping one hop short.
- **Fix:** the plaza's sweep test also fails on any standing place over the reach (it failed on the old props), the
  steps are gone (loose cartons, tyres moved by the booths), and `map_escape_probe.gd` now lists every standing place
  0.9 m and more up (`raised`), the tops a roost check starts from.
- **Docs:** [Map review, collision hygiene](../godot/map-review.md#7-collision-hygiene-out-of-bounds-and-skipped-doors).
