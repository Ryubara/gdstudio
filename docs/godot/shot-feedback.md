# Shot feedback: flash, impacts and shake

Found building Deadnight's muzzle flash, bullet impacts and camera shake in Godot 4.7 with the Compatibility renderer
(the game's own page is its `docs/research/shot-feedback.md`).

## Muzzle flash

- **Every firearm model carries a `Muzzle` empty** at the barrel tip, -Z out of the barrel, placed by whoever models
  the weapon. The flash hangs on it in every view. A server-side "muzzle" offset from the body is only the start of
  the shot's ray: drawn there, the flash can sit inside the player's body as the shoulder camera sees it, and the depth
  test hides it whole.
- **A toon flash is one shader on a `QuadMesh`**: `unshaded`, `blend_add`, `depth_draw_never`, `cull_disabled`. The
  shape is a polar star (`abs(cos(angle * spikes / 2))` as the edge radius) in two flat colours, its edge anti-aliased
  with `fwidth(dist)`. No texture, one transparent quad per piece. Turn it to the camera in script when the shot fires
  (`Basis.looking_at`), not in the shader, when it needs its own roll or must follow the barrel.
- **`top_level = true` quads ignore a scaled parent.** A flash under a weapon marker (the hold scales the weapon) is
  placed with `global_transform` and an explicit size, so the weapon's scale never changes the flash.
- **A flash light counts against the Compatibility per-object light cap** ([Lighting in Compatibility](compat-lighting.md)):
  allow one at a time on the whole map, and keep it short in range.

## Impacts

- **Billboard in `vertex()`** for a puff that keeps its node's scale and faces the camera; it works in Compatibility:

  ```glsl
  MODELVIEW_MATRIX = VIEW_MATRIX * mat4(
      INV_VIEW_MATRIX[0] * length(MODEL_MATRIX[0].xyz),
      INV_VIEW_MATRIX[1] * length(MODEL_MATRIX[1].xyz),
      INV_VIEW_MATRIX[2] * length(MODEL_MATRIX[2].xyz),
      MODEL_MATRIX[3]);
  ```

- **Pool impacts** (a fixed number of slots) and size them against the character in a capture; an untested placeholder
  is easily ten times too big.

## Camera shake

- **Trauma style, rotation only, on the lens node.** The rig keeps the unshaken transform, and the aim ray reads that,
  so shots stay on the crosshair under full shake.
- **Read `FastNoiseLite` at an accumulated time**, not `TIME`, so the shake is the same in tests and in Movie Maker.
- **Every amount is exported** (per weapon and on the player tuning) and a player setting scales it to zero; reduced
  motion turns it off.

## Capturing it

- **Movie Maker's file numbers are not a script's own frame count**: the frames spent loading are numbered too. Print
  `Engine.get_frames_drawn()` for the file to keep. A 2-frame flash shows in exactly two files at a fixed 10 fps.
- **The exit-time "still in use" log flakes under load**: a headless run beside other Godot processes printed audio
  streams still playing at quit; alone it was clean. Judge a leak check on a quiet machine.
