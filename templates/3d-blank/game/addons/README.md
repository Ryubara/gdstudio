# addons

Code that is not ours alone.

- `gds_*`: the kit's own addons, copied here by `gds sync` and tracked (`gds_ui` today). Change them in the kit, never
  here. A synced addon is not enabled by the sync: `gds_ui` is enabled in this `project.godot` (its plugin under
  `[editor_plugins]`, the `UIRouter` autoload under `[autoload]`), and `gds check layout` fails when either is removed,
  because its scripts do not parse without the autoload
  ([Sync](https://github.com/{KIT_REPO}/blob/main/docs/studio/sync.md#addons)).
- `phantom_camera`: [Phantom Camera](https://phantom-camera.dev) 0.11.0.4 (MIT), committed as released without its demo
  scenes and C# scripts; its licence entry is `phantom_camera/LICENSE.md`. Every camera of the game is a
  `PhantomCamera3D` under one `PhantomCameraHost` on the `Camera3D`: the host picks the one with the highest priority
  and blends to it. Its plugin and its `PhantomCameraManager` autoload are registered in `project.godot`, and
  `gds check layout` fails when either is removed, as for `gds_ui`.
- `prototype_grid`: the template's own editor plugin; it sets the 3D editor's translate snap to the grid's cell size
  (Project Settings > Shader Globals > `prototype_cell_size`). Left out of the export.
- `gdUnit4` and `godot_mcp`: installed by `gds workspace init`, untracked (they are in `.git/info/exclude`), and left
  out of the export.
- A third-party addon we commit needs a licence entry beside it.
