---
areas: [gameplay, tests]
---
# A wreck out of the body's reach was climbed at the inside corner of two

2026-11-03

- **Saw:** Deadnight #855 put a row of wrecks on a field flank, each a 1.3 m box, over the real body's measured reach
  (1.25 m), and turned the last one across the row's end. The region escape sweep stood the body on top of it in one
  sprint-jump from the floor, at the inside corner where the two met. A lone 1.3 m block is never climbed.
- **Cause:** the reach was measured at a single block's straight edge (`ledge_probe.gd`). At an inside corner the
  capsule touches two faces at once while it rises, and the contacts lift it further than one edge does; "over the
  reach" was taken to mean "out of reach" for any arrangement of such boxes.
- **Fix:** tall pieces stand square and end to end in straight rows, never in an L; the sweep (1.0 m cells, depth 4,
  launch cells only in the changed stretch, `--region`) then stood nothing on a row. A piece over the reach is still
  judged by the sweep, not by its height, and a wreck's top was also checked with the dead (`roost_probe.gd`: 5 blows
  in 40 s, so not a roost even if reached).
- **Docs:** [Map review, collision hygiene](../engines/godot/map-review.md#7-collision-hygiene-out-of-bounds-and-skipped-doors).
