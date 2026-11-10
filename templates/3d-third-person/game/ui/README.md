# ui

Screens, the HUD and their skin: `ui/<area>/` for each (`ui/hud/`, `ui/menus/`), `ui/skin/` for tokens and themes.

- May use everything below it (`core/`, `gameplay/`, `world/`); nothing below uses `ui/`.
- A scene with a script shares its name and folder.

The template has `ui/touch/` (the phone controls, from 3D Blank: a floating stick, a look drag and buttons that press
the game's input actions), `ui/hud/item_counter.tscn` (what the player has collected) and `ui/probe/web_probe.gd` (the
state a browser test reads from the web build when the page is opened with `?probe`).
`ui/menus/` holds the main menu, the loading screen, the pause menu, the settings screen and the `ScreenHost` that opens
screens over the game (the project starts at `ui/menus/menu_scene.tscn`); the options they show are kept by the
`Settings` autoload in `core/settings/`.
