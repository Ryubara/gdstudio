# ui

Screens, the HUD and their skin: `ui/<area>/` for each (`ui/hud/`, `ui/menus/`), `ui/skin/` for tokens and themes.

- May use everything below it (`core/`, `gameplay/`, `world/`); nothing below uses `ui/`.
- A scene with a script shares its name and folder.
- `ui/touch/` is the phone controls every template shares: instance `touch_controls.tscn`, set the action each of its
  buttons presses, and connect `look_turned` to whatever turns the view. It is a scene of real nodes (the stick, two
  zones, a button each) that you arrange in the 2D editor, and the editor shows it even when `show_mode` hides it in
  the game. Numbers are in the inspector (when it shows, stick, look, opacity, margin).
