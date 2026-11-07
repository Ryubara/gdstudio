# addons

Code that is not ours alone.

- `gds_*`: the kit's own addons, copied here by `gds sync` and tracked (`gds_ui` today). Change them in the kit, never
  here. A synced addon is not enabled for you: a game that wants one adds its plugin and autoload to its own
  `project.godot` ([Sync](https://github.com/{KIT_REPO}/blob/main/docs/sync.md#addons)).
- `gdUnit4` and `godot_mcp`: installed by `gds workspace init`, untracked (they are in `.git/info/exclude`), and left
  out of the export.
- A third-party addon we commit needs a licence entry beside it.
