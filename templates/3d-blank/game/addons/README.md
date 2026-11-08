# addons

Code that is not ours alone.

- `gds_*`: the kit's own addons, copied here by `gds sync` and tracked (`gds_ui` today). Change them in the kit, never
  here. A synced addon is not enabled by the sync: `gds_ui` is enabled in this `project.godot` (its plugin under
  `[editor_plugins]`, the `UIRouter` autoload under `[autoload]`), and `gds check layout` fails when either is removed,
  because its scripts do not parse without the autoload
  ([Sync](https://github.com/{KIT_REPO}/blob/main/docs/studio/sync.md#addons)).
- `gdUnit4` and `godot_mcp`: installed by `gds workspace init`, untracked (they are in `.git/info/exclude`), and left
  out of the export.
- A third-party addon we commit needs a licence entry beside it.
