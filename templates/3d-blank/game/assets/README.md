# assets

`assets/<domain>/<subject>/`: the domain is the kind of thing (`models`, `textures`, `materials`, `shaders`, `audio`,
`ui`, `branding`), the subject is what it is for (`prototype`, `player`). Names are `<subject>_<variant>_<n>`.

- Every third-party folder carries a `LICENSE.md` naming the source and licence; a file without one is not committed.
- Binary assets go through Git LFS (`.gitattributes` lists the types).
- `assets/shaders/prototype/` and `assets/materials/prototype/` are the template's prototype surface: one world-space
  grid shader and a material per colour.
- `assets/audio/wind/` is a gusty wind loop of 28 s for the `Ambient` bus, generated with ElevenLabs Sound Effects on
  the studio's paid plan: commercial use in a game allowed, no attribution required, not to be shared on its own as a
  sound file (its `LICENSE.md` says how it was made and what the terms allow; the kit's
  `docs/gamedev/audio/sound-effects.md` has the recipe).
