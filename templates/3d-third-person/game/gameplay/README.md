# gameplay

One folder per feature: `gameplay/<feature>/`, holding the feature's scripts, scenes and tuning resources together
(`player/player.gd`, `player/player.tscn`, `player/player_tuning.tres`). A scene with a script shares its name and
folder.

- Split a feature when a folder passes about 30 scripts with clear clusters.
- May use `core/` and `world/`; never `ui/`.

The template has a character and the map's components:

- `player/`: the character (`Player`, its `PlayerTuning`, `PlayerAnimation`, `PlayerCamera`, `Interactor`,
  `StepClimber`, `CharacterClips`). The numbers a developer tunes are in `player_tuning.tres`.
- `weapon/`, `projectile/`, `target/`: a `Weapon` that fires `Projectile` spheres from a muzzle marker toward the crosshair,
  and a `Target` that falls over when hit. They work with any model: point `Weapon.muzzle` at a marker.
- `impacts/`: an `Impacts` that makes a mark, an effect and a sound where a `Projectile` lands, by the kind of surface
  (`ImpactSurface` nodes; a body says `surface` in its metadata or a group). Marks are quads on the body that was hit.
- `net/`: the bytes of an online game (`NetWire`, `CommandCodec`, `SnapshotCodec`) and the limits of one connection
  (`PeerLimits`, `NetLimits`), plain code with no node, socket or clock; `player/player_command.gd` is what one tick
  of a player asks for. The layout of every message is the comment at the top of `net/net_wire.gd`.
- `camera_zone/`: hands the view to another Phantom Camera while the player stands in a trigger zone.
- `door`, `pickup`, `trigger_zone`, `moving_platform`, `spawn_point` and `physics_prop`: map components, each a scene
  with a script and inspector groups, working on its own. Their parts are nodes of the scene (a door's `Panel`,
  `Shape` and `Sensor`), so open the scene to restyle one; the `@tool` scripts size them from the inspector in the
  editor too. Connect their signals in the editor's Node dock (a trigger's `activated` to a door's `open`).
