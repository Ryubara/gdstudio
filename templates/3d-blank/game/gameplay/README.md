# gameplay

One folder per feature: `gameplay/<feature>/`, holding the feature's scripts, scenes and tuning resources together
(`player/player.gd`, `player/player.tscn`, `player/player_tuning.tres`). A scene with a script shares its name and
folder.

- Split a feature when a folder passes about 30 scripts with clear clusters.
- May use `core/` and `world/`; never `ui/`.

The template's map components live here, each a scene with a script and inspector groups, working on its own:
`door`, `pickup`, `trigger_zone`, `moving_platform`, `spawn_point` and `physics_prop`. Connect their signals in the
editor's Node dock (a trigger's `activated` to a door's `open`).
