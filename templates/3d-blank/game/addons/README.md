# addons

Code that is not ours alone.

- `gds_*`: the kit's own addons, copied here by `gds sync` (once the kit has any) and tracked. Change them in the
  kit, never here.
- `gdUnit4` and `godot_mcp`: installed by `gds workspace init`, untracked (they are in `.git/info/exclude`), and left
  out of the export.
- A third-party addon we commit needs a licence entry beside it.
