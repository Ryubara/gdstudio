# assets

`assets/<domain>/<subject>/`: the domain is the kind of thing (`models`, `textures`, `materials`, `shaders`, `audio`,
`ui`, `branding`), the subject is what it is for (`prototype`, `player`). Names are `<subject>_<variant>_<n>`.

- Every third-party folder carries a `LICENSE.md` naming the source and licence; a file without one is not committed.
- Binary assets go through Git LFS (`.gitattributes` lists the types).
- `assets/shaders/prototype/` and `assets/materials/prototype/` are the template's prototype surface: one world-space
  grid shader and a material per colour.
- `assets/audio/wind/` is a soft wind loop of 10.5 s for the `Ambient` bus, generated with ElevenLabs Sound Effects on
  the free tier: attribution required, not licensed for commercial use. **Temporary: replace or relicense it before
  any commercial release** (its `LICENSE.md` says how it was made; the kit's `docs/gamedev/audio/sound-effects.md`
  has the recipe), and name ElevenLabs on the Credits screen until then.
