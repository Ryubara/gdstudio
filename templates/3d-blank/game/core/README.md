# core

Autoloads and foundations that every feature may use: settings, services, small helpers.

- `audio_settings/`: the bus volumes as inspector settings.
- `camera_shake/`: the universal screen shake (`CameraShake`, `ShakePreset` and a few presets): `CameraShake.shake(preset,
  at)` from anywhere, applied by the camera rig that owns the node; the kit's `engines/godot/camera.md#shake-component`.

- No words from the game's design (no `zombie`, `weapon`, `round`): if the name needs the game, it belongs in
  `gameplay/`.
- Imports nothing from `gameplay/`, `world/`, `net/` or `ui/`. The dependency order is in the kit's
  `docs/engines/godot/project-conventions.md`, and `gds check layout` fails a reference that points the wrong way.
