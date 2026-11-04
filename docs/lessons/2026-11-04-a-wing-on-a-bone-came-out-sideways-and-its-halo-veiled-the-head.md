---
areas: [godot, blender]
---
# A wing built "up and out" on a bone came out sideways, and its halo veiled the head

2026-11-04

- **Saw:** a mesh built with its length up the Y axis and mounted on the Soldier's `Torso` bone (a `BoneAttachment3D`)
  lay flat, then, with the rest axes cancelled but the feathers' width along the wrong axis, stood edge-on as spikes.
  A billboard glow quad centred on the wings sat between the camera (behind the wearer) and the body and veiled the head.
- **Cause:** a bone's axes are the rig's, not the world's; a flat fan has a plane, and "width" must lie in it.
  The camera in a third-person view is on the back side, so anything on the back is in front of the head.
- **Fix:** cancel the attachment's rest axes (`root.basis = (skeleton.global_basis * bone rest basis).inverse() *
  model.global_basis`), build the fan in the plane that faces the camera, look at a still from behind and from the
  side before measuring, and push a halo into the chest so the body hides it.
- **Docs:** [Compatibility lighting](../godot/compat-lighting.md#glow-on-the-web-and-what-a-wing-of-fire-costs-deadnight-1053).
