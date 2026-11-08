# gameplay

One folder per feature: `gameplay/<feature>/`, holding the feature's scripts, scenes and tuning resources together
(`player/player.gd`, `player/player.tscn`, `player/player_tuning.tres`). A scene with a script shares its name and
folder.

- Split a feature when a folder passes about 30 scripts with clear clusters.
- May use `core/` and `world/`; never `ui/`.

This template has no gameplay yet. The kit's other templates start from this one and add it: 3D Third Person has a
character, a camera and six map components.
