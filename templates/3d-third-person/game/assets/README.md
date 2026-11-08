# assets

`assets/<domain>/<subject>/`: the domain is the kind of thing (`models`, `textures`, `materials`, `shaders`, `audio`,
`ui`, `branding`), the subject is what it is for (`prototype`, `player`). Names are `<subject>_<variant>_<n>`.

- Every third-party folder carries a `LICENSE.md` naming the source and licence; a file without one is not committed.
- Binary assets go through Git LFS (`.gitattributes` lists the types).
- `assets/shaders/prototype/` and `assets/materials/prototype/` are the template's prototype surface: one world-space
  grid shader and a material per colour.
- `assets/characters/mannequin/` is Quaternius's mannequin and `assets/animation/universal/` the Universal Animation
  Library 1 and 2 (CC0, each with a `LICENSE.md`): the character's mesh and its 86 clips.
- `assets/audio/coin/` (a coin pickup, four variants) and `assets/audio/footsteps/` (ten single steps on a hard floor)
  are generated with ElevenLabs Sound Effects on the free tier, like the base's wind: attribution required, not
  licensed for commercial use. **Temporary: replace or relicense them before any commercial release**, and name
  ElevenLabs on the Credits screen until then.
