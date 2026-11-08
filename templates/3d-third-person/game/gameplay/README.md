# gameplay

One folder per feature: `gameplay/<feature>/`, holding the feature's scripts, scenes and tuning resources together
(`player/player.gd`, `player/player.tscn`, `player/player_tuning.tres`). A scene with a script shares its name and
folder.

- Split a feature when a folder passes about 30 scripts with clear clusters.
- May use `core/` and `world/`; never `ui/`.

The template has a character and the map's components:

- `player/`: the character (`Player`, its `PlayerTuning`, `PlayerAnimation`, `PlayerCamera`, `Interactor`,
  `StepClimber`, `CharacterClips`). The numbers a developer tunes are in `player_tuning.tres`.
- `camera_zone/`: hands the view to another Phantom Camera while the player stands in a trigger zone.
- `door`, `pickup`, `trigger_zone`, `moving_platform`, `spawn_point` and `physics_prop`: map components, each a scene
  with a script and inspector groups, working on its own. Connect their signals in the editor's Node dock (a
  trigger's `activated` to a door's `open`).
