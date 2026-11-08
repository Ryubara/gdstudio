---
areas: [camera, godot-ui]
---
# Hip fire was a second, partial aim, and the gun snapped into aim

2026-11-01

- **Saw:** the maintainer, playing: firing without aiming did not raise the gun into the aim pose; pressing aim made
  the gun jump to its aim position in one frame; the camera zoomed only part way on hip fire and took much longer to
  zoom out than releasing aim.
- **Cause:** each system decided "is the player aiming" on its own. The camera had a second spring for hip fire (half
  the aim zoom, in at 14 and out at 7 against the aim's 24, held 0.8 s after the last shot); the animation and the hands
  read only the aim button. In the hands, the aim yaw switched between body and camera yaw and the support-hand
  convergence was a bool, so only the legs' blend eased.
- **Fix:** one eased aim weight per character, entered by the aim button or a shot within the hip-fire hold, read by
  the camera, the body and the hands; the aim button only skips the entry because the weight is already full. Pose
  inputs are blended by the weight. Tests: hip fire reaches the same placement and pose as aiming and releases in the
  same time; the hand target's per-frame change stays under a bound (Deadnight #300).
- **Docs:** [What the maintainer caught](../studio/maintainer-corrections.md).
