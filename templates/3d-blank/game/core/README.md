# core

Autoloads and foundations that every feature may use: settings, services, small helpers.

- No words from the game's design (no `zombie`, `weapon`, `round`): if the name needs the game, it belongs in
  `gameplay/`.
- Imports nothing from `gameplay/`, `world/`, `net/` or `ui/`. The dependency order is in the kit's
  `docs/godot/project-conventions.md`, and `gds check layout` fails a reference that points the wrong way.
