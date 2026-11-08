# ui

Screens, the HUD and their skin: `ui/<area>/` for each (`ui/hud/`, `ui/menus/`), `ui/skin/` for tokens and themes.

- May use everything below it (`core/`, `gameplay/`, `world/`); nothing below uses `ui/`.
- A scene with a script shares its name and folder.
- `ui/touch/` is the phone controls every template shares: instance `touch_controls.tscn`, list its buttons and the
  actions it presses, and connect `look_turned` to whatever turns the view. Settings are in the inspector (when it
  shows, stick, look, buttons).
