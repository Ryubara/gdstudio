# assets

`assets/<domain>/<subject>/`: the domain is the kind of thing (`models`, `textures`, `materials`, `shaders`, `audio`,
`ui`, `branding`), the subject is what it is for (`prototype`, `player`). Names are `<subject>_<variant>_<n>`.

- Every third-party folder carries a `LICENSE.md` naming the source and licence; a file without one is not committed.
- Binary assets go through Git LFS (`.gitattributes` lists the types).
- `assets/shaders/prototype/` and `assets/materials/prototype/` are the template's prototype surface: one world-space
  grid shader and a material per colour.
