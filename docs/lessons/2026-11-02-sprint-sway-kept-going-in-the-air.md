---
areas: [camera, process]
---
# The sprint sway kept going in the air

2026-11-02

- **Saw:** with Shift held through a sprint-jump, the camera kept its footfall sway (0.425 degrees, the same as on the
  ground) for the whole jump. The maintainer wanted the shake to stop whenever the player is in the air.
- **Cause:** `SprintSway.step` took only the sprint state and horizontal speed. In the air the body keeps its
  `sprinting` flag and its speed, so nothing told the sway the feet had left the ground; the motion state had
  `on_floor`, but it was never passed to the camera rig.
- **Fix:** the sway takes the grounded state and fades out on the first airborne tick; a test steps through that tick
  and the capture includes a sprint-jump with the key held (Deadnight #426).
- **Docs:** [What the maintainer caught](../research/maintainer-corrections.md).
