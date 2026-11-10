# core

Autoloads and foundations that every feature may use: settings, services, small helpers.

- `audio_settings/`: the bus volumes as inspector settings.
- `camera_shake/presets/`: the game's own shake presets (`.tres`) for the universal screen shake, whose scripts
  (`CameraShake`, `ShakePreset`) are in the synced `addons/gds_game/camera_shake/`: `CameraShake.shake(preset, at)` from
  anywhere, applied by the camera rig that owns the node; the kit's `engines/godot/camera.md#shake-component`.

- No words from the game's design (no `zombie`, `weapon`, `round`): if the name needs the game, it belongs in
  `gameplay/`.
- Imports nothing from `gameplay/`, `world/`, `net/` or `ui/`. The dependency order is in the kit's
  `docs/engines/godot/project-conventions.md`, and `gds check layout` fails a reference that points the wrong way.
