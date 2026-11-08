---
areas: [godot, tests]
---
# A billboard halo wider than its gap to the wall swung through the wall

2026-11-03

- **Saw:** the maintainer fixed it by hand in the editor (Deadnight #703): a neon sign's glow halo bled through the
  wall, and agents must check for this from now on. The concession's SNACKS sign
  showed a pink bloom in the room behind its wall and a pink cloud hanging in the air past the wall's end.
- **Cause:** the sign's halo was a 9 x 4 m additive quad with `billboard = true`, 0.3 m in front of a sign that sits
  0.1 m off the wall. A billboard turns to face the camera about its own centre, so seen from the side its 4.5 m
  half-width lies across the wall's plane: about 4 m of it is behind the wall and the rest hangs past the wall's ends.
  An additive, depth-tested quad draws wherever nothing nearer hides it, so from inside the room (or from the field
  beside the wall) the part behind the wall is simply in front of what the camera sees. The sign was only ever shot
  from the front, where a billboard is flat against the wall and looks right. Captured from inside and along the wall
  with the halo hidden and shown, the halo alone changed 12,104 and 63,440 pixels of two room views before, and 0 and
  0 after the fix. A second source stayed: the sign's `OmniLight3D` has no shadows in Compatibility (and its energy
  went from 2.2 to 9.6 in the same edit), so it still lights the room's ceiling and the wall's inside edge through the
  wall in a hard-edged wedge.
- **Fix:** the maintainer's: `billboard = false` (a flat quad lying against the wall, a thin disc edge-on from the
  side), a lower energy and a higher falloff. The scene's `energy` is only the first value: `LotNeonSign._apply` sets
  it every tick from `LightTuning.neon_halo_energy`, so change that to change the halo in the game. For any glow,
  halo, flare or additive card, before calling it done: compare its half-size with its distance to every wall near it
  (a billboard turns about its centre, so the half-size is the reach), and capture it from the room behind the wall,
  along the wall at eye height and from above, with the glow hidden and shown, counting the pixels that change.
- **Docs:** [Compatibility lighting](../godot/compat-lighting.md#lamps-in-a-game-what-looks-like-light-and-what-is-light).
  A hand edit in the editor of the lot scene is lost the next time `tools/world/build_greybox.py` runs, so a hand edit
  of a generated scene goes into its generator in the same pull request.
