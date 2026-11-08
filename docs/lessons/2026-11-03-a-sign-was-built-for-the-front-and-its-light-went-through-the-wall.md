---
areas: [godot, tests]
---
# A sign was built and shot for its front only, and its light and halo went through the wall

2026-11-03

- **Saw:** the maintainer, a second time after #703: light must not bleed through walls, and a sign's
  glow halo still did because nobody considered it when it was made (Deadnight #832). The SNACKS sign's omni light (energy
  9.6, range 10, 1.2 m outside the wall) lit the stand's floor and roof pink from behind the wall (up to 3 energy; 140 000
  to 270 000 pixels of every room view with the light hidden and shown), and its flat halo, 4 m tall on a 4 m wall, stood
  in the air over the roof from behind.
- **Cause:** a glow is judged from the side its picture is for. The sign, the pools and the cones were each built and
  captured from the front, and the #703 lesson fixed the billboard halo only. The Compatibility renderer has no shadow,
  so the depth test is the only wall a glow card has and the sphere of a light is the only limit of a lamp: nobody asks
  where a card or a range ends against the wall. The same fault, smaller, was in six of the small map's pools, cones and
  halos (a lamp one metre from a wall with a 3.6 m pool).
- **Fix:** a lamp that hangs on the outside of a wall is a spot facing out (its cone cannot pass the plane of its
  apex); a card carries clip planes found from the wall boxes (`GlowClip`), so it stops at the wall it stands near or
  is mounted on. A test samples every additive card of both maps against the walls (a point behind a wall seen from
  its own lamp, a wall-mounted card hanging past its wall) and every light against the surfaces it reaches through a
  wall, with a table of the leaks that remain (unshadowed room lamps reach the next room by their range) that can only
  shrink. Judge a new glow or light by the numbers, not the front view: sample its card and its range against every
  wall within reach, and capture it from the room behind with the glow hidden and shown.
- **Docs:** [Compatibility lighting](../engines/godot/compat-lighting.md#lamps-in-a-game-what-looks-like-light-and-what-is-light).
