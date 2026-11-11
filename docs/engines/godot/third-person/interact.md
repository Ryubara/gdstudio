# Using things

<!-- new section: split out of the character page when it reached the size limit (gdstudio #1029) -->

How a 3D Third Person character uses a door, a lever or anything else with its interact button. Part of
[the 3D Third Person template](../third-person-template.md).

## The component {#interactable}

<!-- new section: a door joined a group and the character called `interact` and `interact_point` on it by name; nothing
     said how a lever or a chest becomes usable without a script of its own (gdstudio #925) -->

Anything a character uses with its interact button carries an `Interactable` (`addons/gds_game/interact/`, synced into
every game): an `Area3D` on the Sensors layer (7) with a shape, that makes its parent usable. The character's
`Interactor` (`gameplay/character/interactor.gd`) asks the physics space once per press for the areas on
`interact_mask` (Sensors) inside a cylinder of the tuning's `interact_reach` around it (`reach_height` up and down),
keeps the `Interactable`s that are `enabled`, measures each one's `reach_point()` on the ground plane and takes the
nearest within `half_angle` of where the character faces. `Character.interact()` calls its `interact(self)`, which says
`interacted(by)`; the character says `interacted(target)` with the `Interactable`'s parent and returns it. Nothing
joins a group and nothing is called by a method name, so a lever is a `Node3D` with an `Interactable` child and a
shape, its `interacted` signal connected in the scene to whatever it moves.

- **The inspector, on `Interactable`:** `prompt` ("Use"; the door says "Open"), `enabled` (off: passed over, and
  `interact()` does nothing) and `point` (a node that stays put to measure the reach to, for a parent that moves as it
  is used; empty: the area's own place). Its shape is a child `CollisionShape3D`; with none it warns.
- **On `Interactor`:** `half_angle` (75°), `reach_height` (1.5 m) and `interact_mask` (Sensors). Pickups and trigger
  zones share the layer and are skipped by type; one search looks at 32 areas at most.
- **The door** has an `Interactable` with a 0.5 m sphere at 1 m, its `interacted` connected to `Door.interact()` in
  `door.tscn`; `player_can_use` switches it on and off, and the door keeps it where the closed door stands as the panel
  moves, so an open gate is closed from where it was opened. A door with `player_can_use` on and no `Interactable`
  warns.
- **What it costs:** one shape query per press of the interact button, nothing a frame. An `Area3D` with `monitoring`
  off (it senses nothing) is still found by `PhysicsDirectSpaceState3D.intersect_shape()` with `collide_with_areas`
  on, a physics tick after it enters the tree (Jolt, 4.7; `test_interactable_alone.gd`).
- **Capture:** `tools/capture/components_tour.tscn` (two range targets shot down through their `Health`, one taking
  two shots, then a lever that is a `Node3D` with an `Interactable` and no script, pulled with the button):
  `gds capture frames --project game --scene res://tools/capture/components_tour.tscn --seconds 14`.
- **Tests:** `godot/tests/gds_game/test_interactable_alone.gd` (the signal, off, the fixed point, a query on its layer
  finds it, the warning, the pins); `tests/gameplay/test_hit_and_interact_components.gd` (a `Node3D` with no script
  and an `Interactable` is found and used by a character; a door without one warns and is not found); `test_door.gd`
  (the reach measured from the closed gate).
