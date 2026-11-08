---
areas: [blender, process]
---
# A slit in a boot was blamed on rays for three builds

2026-11-04

- **Saw:** the trouser leg showed through a slit in the front of a tall boot's shaft (Deadnight #1078), in a sheet taken
  at `Idle`. Sampling more heights, more bearings and a further ray start each changed nothing.
- **Cause:** the sheet was a posed frame and the guess assumed the rest pose. The shaft was blended to the foot up past
  the trouser hem, so a bent ankle left it behind while the hem went with the shin.
- **Fix:** the shaft stays on the shin down past the hem and only the ring in the foot bends; the three ray changes were
  reverted. When a change does nothing, the next step is a look at another pose, not a finer version of the same
  change: a side view had shown the kink all along.
- **Docs:** [Character variants, clothes that stand off the body](../tools/blender/variants.md).
