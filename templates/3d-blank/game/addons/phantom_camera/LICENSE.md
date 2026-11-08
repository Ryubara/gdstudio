# Phantom Camera

- Addon: "Phantom Camera" by Marcus Skov (ramokz), version 0.11.0.4
- Source: <https://github.com/ramokz/phantom-camera>, tag `v0.11.0.4` (commit
  `d20277eb0f9f7f0068e7aed7d7fe777ab72a0f07`; the release's source archive has sha256
  `3b042b3f4a5a722c40e75b6854c6dad467657d8cdbbd402c9111598a4ac2c82c`)
- Author: Marcus Skov (<https://phantom-camera.dev>)
- Licence: MIT, the addon's own `LICENSE` file beside this one (copyright 2022 Marcus Skov)
- Files: the addon's `addons/phantom_camera/` folder as released, without `examples/` (the addon's demo scenes) and
  without its C# scripts (`*.cs`, the project is GDScript only). Nothing else is changed.

The plugin is enabled and its `PhantomCameraManager` autoload registered in `project.godot`; its update check is off
(`phantom_camera/updater/updater_mode=0`) so the editor does not look for a release: to take a new version, replace the
folder with the release's, update this entry and run the tests.
