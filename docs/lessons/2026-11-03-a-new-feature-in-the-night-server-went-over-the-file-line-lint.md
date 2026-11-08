---
areas: [gameplay, tools]
---
# Nineteen lines for a perk put `night_server.gd` over gdlint's 1000-line limit

2026-11-03

- **Saw:** Deadnight #687: `uvx pre-commit run --all-files` failed gdlint: `night_server.gd:1049: Max allowed file lines
  num (1000) exceeded` and the same for `game_rules.gd` at 1005. The files had been at 998 and 997.
- **Cause:** the hot files have no room: every feature adds its few lines there, and the lint counts them all.
- **Fix:** the new behaviour went into classes of its own (`ShockPlay`, `PerkPlay`, `PerkEffects`) with one call each in
  the hot file, the event documentation moved to the new classes, and `night_server.gd` got
  `# gdlint:disable=max-file-lines` (the way `game_rules.gd` carries `max-public-methods`) because the remaining lines
  were the frame's two fields and the hooks. Check the line counts before writing the feature, not after.
- **Check for next time:** `wc -l` the hot files (`night_server.gd`, `game_rules.gd`, `night.gd`) before putting code
  in them; put the logic in a class and the call in the file.
- **Docs:** [Hooks](../studio/hooks.md).
