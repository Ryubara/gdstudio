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

## Bullet impacts and marks in 3D Third Person {#impact-marks}

<!-- new section: the template's pistol left nothing where a shot landed (gdstudio #875); the Impacts and Blood sections
     above are Deadnight's toon, server-driven versions, and none said how a Decal behaves in Compatibility, what a mark
     does on a moving body, or how a hit picks its surface -->

What the 3D Third Person template does (`gameplay/impacts/`; its inspector list is on
[the template page](third-person-template.md#impacts)). Measured in Godot 4.7.2 on Windows, an RTX 5080, in a spike
(`Decal` nodes on a floor, a wall, a cylinder and a moving box, drawn in each renderer) and in the template's own
captures; the research with its sources is in the pull request of #875.

| Route | Forward+ | Compatibility (the web build) | Moving bodies | Verdict |
| --- | --- | --- | --- | --- |
| `Decal` node | draws, wraps a cylinder and a corner, clipped at an edge | **draws nothing, with no error** (the docs say Forward+ and Mobile only) | a child of the body follows it, but projects on whatever is in its box (a wall beside the crate) | desktop only; not used |
| Pooled quad (`MeshInstance3D`) a child of the hit body, one shader | draws | draws, the same frame | follows the body, goes when it is freed | **used** |
| One `MultiMeshInstance3D` of quads | draws | draws | one draw call, but a multimesh is one transform space: a mark on a moving body needs a multimesh of its own | for a map that never moves |
| A mesh clipped to the surface | draws | draws | heavy per hit | only if marks must bend round a curve |

- **A mark is a quad whose +Z is the surface normal**, a child of the body that was hit, lifted off it by `surface_offset`
  (4 mm) and, in the shader, by 2 mm a metre of distance to the camera (a fixed lift flickers far away). It is a
  `MeshInstance3D` of a shared unit `QuadMesh` scaled in x and y (z stays 1, so the lift is in metres) with the
  surface's `ShaderMaterial`. The shader draws a hole and a rough ring, or `mark_texture` when `use_texture` is on, and
  fades by an **instance uniform** (`instance uniform float fade`, set with `set_instance_shader_parameter`), which
  works in Compatibility, so every mark of a surface shares one material and one program. `GeometryInstance3D.transparency`
  does not: it is Forward+ only.
- **Marks come from a pool with a cap**: past `max_marks` the oldest node is taken out of its parent and put on the new
  hit (nothing is allocated); a mark that lives out `mark_lifetime` fades over `mark_fade_time` and is freed (0 keeps it
  until a newer one needs the place). A freed body takes its marks with it; the list forgets them at the next hit and
  tick.
- **A hit picks its surface** from the first node, from the body up to the root, with the metadata `surface` (a name)
  or in a group of that name; the default surface when none says. The name is only a key: any number of `ImpactSurface`
  nodes under the `Impacts`. Each holds its mark material, an effect node (`CPUParticles3D` or `GPUParticles3D`, one
  shot) and an `AudioStreamPlayer3D`, so a developer restyles them in the editor.
- **Effects are copies of the template node**, made lazily (`pool_size`), and **every hit writes the template's changed
  properties onto the copy it uses**, so an edit made in the remote inspector shows in the next hit. A one-time
  `duplicate()` copies once and ignores later edits; the copy step only sets a property that differs (setting a
  particle `amount` rebuilds buffers).
- **`CPUParticles3D` is the default effect** (8 to 10 small unshaded meshes, one shot): on the web a `GPUParticles3D`
  adds programs of its own ([first-use hitches](first-use-hitches.md)); both work, since the surface calls `restart()`.
- **The bones of the ragdoll (layer 16) take no mark**: a projectile's mask is the level (layer 1), so a shot goes
  through them and marks what is behind. A `CharacterBody3D` takes no mark either (its mesh is animated; a mark would
  stay in the air), but its surface still plays the effect and the sound. A game that wants wounds sets the body's
  surface (`flesh`) and gives it a blood effect: the quad cannot follow a skinned mesh.
- **Known limits of a quad:** it is flat, so on a curved surface it touches at its middle and floats at its edge (a 12
  cm mark on a pillar of 1 m diameter lifts 3.6 mm at the rim: hardly seen); near the edge of a block it overhangs into
  the air (a `Decal` would clip). The first mark of a material builds its program (the first-use hitch: show one in a
  loading screen on the web).

- **Approach:** Make marks flat quads on the hit body with an instance-uniform shader rather than `Decal`s when the game
  ships to the web or phones, and prove the route with a one-scene spike in both renderers before building. **Watch out
  for:** `Decal` is Forward+ and Mobile only: in Compatibility the spike drew none of its 40 decals and printed no error,
  so a mark system built on it would have shown nothing in the web build while every desktop test passed. **Seen:**
  gdstudio #875, 2026-11-10.
- **Approach:** Test a mark system with real projectiles in a small arena (a wall, a floor, a `PhysicsProp`, a
  `MovingPlatform`): read the mark's parent, its `global_basis.z` against the normal, its place against the body after
  40 ticks, and age a mark by writing `mark.age` instead of waiting out a lifetime. **Watch out for:** a shot at a map's
  wall from the spawn hit another block first; shoot from straight above the thing under test. A shader's
  `get_shader_uniform_list` lists neither instance uniforms nor groups (read the source for `fade`), and an untyped
  `Array.sort()` of `StringName` keys did not sort alphabetically (collect `String`s). **Seen:** gdstudio #875,
  2026-11-10.

## Camera shake {#camera-shake}

- **Trauma style, rotation only, on the lens node.** The rig keeps the unshaken transform, and the aim ray reads that,
  so shots stay on the crosshair under full shake.
- **Read `FastNoiseLite` at an accumulated time**, not `TIME`, so the shake is the same in tests and in Movie Maker.
- **Every amount is exported** (per weapon and on the player tuning) and a player setting scales it to zero; reduced
  motion turns it off.

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
- **Approach:** For a capture of marks or effects, stage each scene with `Player.teleport()` in front of a lit surface and
  put the crosshair on a point by unprojecting it through the lens (`Camera3D.unproject_position`), then read the frames.
  **Watch out for:** a bot that walked across the map got stuck on blocks, and the first burst went into the dark face of
  a wall in shadow, where 12 cm dark holes and 2 cm dust specks were invisible: mark size and dust need a lit,
  mid-tone surface in the frame (the orange blocks of the prototype map). **Seen:** gdstudio #875, 2026-11-10.
