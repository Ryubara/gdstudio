---
areas: [godot, tests]
---
# An autoload named in a new class on the player broke every `-s` tool that loads the player

2026-11-03

- **Saw:** after adding `PerkBottle` (the perk bottle the player's animation holds, Deadnight #912), a capture run with
  `godot -s res://tests/captures/drink_tour.gd` printed `Compile Error: Identifier not found: Audio`, then `Failed to
  compile depended scripts` for `PlayerAnimation` and the player, and ran on with `Nonexistent function 'step' in base
  'Nil'` every frame. The grip solver (`-s res://tests/art/solve_grips.gd`, which reads `PlayerAnimation`'s holds) would
  have died the same way.
- **Cause:** the new class played its sounds with `Audio.play(...)`. A `-s` SceneTree script starts before the
  autoloads exist, so a class that names one does not compile there, and every class that depends on it fails with it.
  The player's chain had named no autoload before, so the tools that load it had always worked.
- **Fix:** in a class the `-s` tools load (the player, its animation, holds and grips), find the service by its node
  and call it: `get_tree().root.get_node_or_null(^"Audio")` and `audio.call(&"play", id, position)`, which compiles
  anywhere and does nothing where there is no service. Run one `-s` tool (the grip solver with `--dry`, or a capture)
  after adding a class to the player.
- **Docs:** [Probes and tools in headless Godot](../engines/godot/headless-probes.md).
