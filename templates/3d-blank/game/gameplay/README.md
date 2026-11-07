# gameplay

One folder per feature: `gameplay/<feature>/`, holding the feature's scripts, scenes and tuning resources together
(`player/player.gd`, `player/player.tscn`, `player/player_tuning.tres`). A scene with a script shares its name and
folder.

- Split a feature when a folder passes about 30 scripts with clear clusters.
- May use `core/` and `world/`; never `ui/`.
