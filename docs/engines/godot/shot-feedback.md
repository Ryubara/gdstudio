# Shot feedback: flash, impacts and shake

Found building Deadnight's muzzle flash, bullet impacts and camera shake in Godot 4.7 with the Compatibility renderer
(the game's own page is its `docs/research/shot-feedback.md`).

## Muzzle flash {#muzzle-flash}

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

## Impacts {#impacts}

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

- **Approach:** List every placeholder effect in an issue when it lands, and capture effects next to the character for
  scale. **Watch out for:** no task owned the effects, so placeholders shipped as final: the muzzle flash was a yellow
  sphere and the impacts far too large, their sizes never compared with the character. **Seen:** Deadnight, 2026-11-01
  (fix: the flash and the impacts were rebuilt and sized in captures beside the character (this page)).

## Blood {#blood}

Found building Deadnight's hit blood (a splash at the wound and marks on the surfaces, Godot 4.7, Compatibility; the
game's page is `docs/research/hit-blood.md`).

- **A splash can be one billboard quad and a fragment shader**, no particles: drops are positions of `progress` and a
  seed (hash per drop), drawn as distances to a short segment, so the same splash shows in a test and on every client,
  and it costs one program instead of the two a `GPUParticles3D` adds on the web.
- **Take the shot's direction into the camera's plane in `vertex()`**
  (`(VIEW_MATRIX * vec4(dir, 0.0)).xy`, normalised). A shot straight away from the camera, the usual one from a shoulder
  camera, has almost no sideways part: open the fan to all round as that part goes to zero (`mix(PI, cone,
  smoothstep(0.15, 0.7, length(d.xy)))`) or the splash is a flat disc.
- **A mark on a surface is a quad whose +Z is the normal, lifted in `vertex()` by a base plus a share of the distance to
  the camera** (1 cm plus 2 mm a metre); a fixed lift flickers far away and floats near. Keep the node's z scale at 1
  so the lift is in metres. `Decal` is not needed, and nothing is made while playing: pool the quads with a cap per
  platform and take the oldest.
- **A held warm-up sample must stand still**: a warm-up frame that builds a program takes seconds and would end a
  half-second splash before it is drawn (`set_process(false)` while it is held).
- **A loop variable named like a method** (`mark`, `splash`) shadows it in GDScript: name the loop
  variable `slot`.

- **Approach:** With the first weapon, list the reference genre's hit feedback (blood or impact on the body, marks, hit
  markers, sounds) and give each its warm-up and its web cost. **Watch out for:** hit feedback was never planned as part
  of the combat loop: shots had numbers, sounds and a reticle but nothing on the body, and no issue listed the genre's
  feedback. **Seen:** Deadnight #618, 2026-11-02 (fix: deadnight #648 added the blood above).

## Camera shake {#camera-shake}

- **Trauma style, rotation only, on the lens node.** The rig keeps the unshaken transform, and the aim ray reads that,
  so shots stay on the crosshair under full shake.
- **Read `FastNoiseLite` at an accumulated time**, not `TIME`, so the shake is the same in tests and in Movie Maker.
- **Every amount is exported** (per weapon and on the player tuning) and a player setting scales it to zero; reduced
  motion turns it off.
- **The templates' version is a shared component**: `CameraShake` and `ShakePreset` resources, one line to play one
  ([Camera: shake component](camera.md#shake-component)).

## Capturing it {#capturing-it}

- **Movie Maker's file numbers are not a script's own frame count**: the frames spent loading are numbered too. Print
  `Engine.get_frames_drawn()` for the file to keep. A 2-frame flash shows in exactly two files at a fixed 10 fps.
- **The exit-time "still in use" log flakes under load**: a headless run beside other Godot processes printed audio
  streams still playing at quit; alone it was clean. Judge a leak check on a quiet machine.
- **Approach:** Make a capture of anything that moves by time wait by time or for the state (`await
  get_tree().create_timer(0.6).timeout`, or `is_instance_valid(night.arrival_show)` until the thing that draws it is
  gone), never for a frame count, and load the scene once headless (`--quit-after 5`) to read its parse errors before a
  windowed capture. **Watch out for:** a bot wheel that opens after 0.18 s held and grows over 0.12 s was shot a third
  open after 24 frames of hold (0.4 s at 60 fps, 0.13 s at 300); a scene that failed to parse kept the window open to
  the 300 s timeout; two captures of a night had black bands 58 px high, the arrival show's own bars, still up 0.45 s
  after `arrival_ended`. **Seen:** Deadnight #642, 2026-11-02; Deadnight, 2026-11-05 (fix: wait for the show to be gone;
  find an unexplained band by its size first, 58.5 / 780 named the constant).
