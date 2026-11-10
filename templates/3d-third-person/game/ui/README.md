# ui

Screens, the HUD and their skin: `ui/<area>/` for each (`ui/hud/`, `ui/menus/`), `ui/skin/` for tokens and themes.

- May use everything below it (`core/`, `gameplay/`, `world/`); nothing below uses `ui/`.
- A scene with a script shares its name and folder.

The template has `ui/touch/` (the phone controls, from 3D Blank: a floating stick, a look drag and buttons that press
the game's input actions), `ui/hud/hud.tscn` (the HUD: regions that hold widgets and one theme; the crosshair, the item
counter and the health and ammo parts are its widgets) and `ui/probe/web_probe.gd` (the state a browser test reads from
the web build when the page is opened with `?probe`; the player rig adds it at run time) and `ui/player_rig/` (the scene
one local player brings: body, camera, touch layer, pause button; `main.tscn` instances it with the world, the HUD and
the screen host). `ui/menus/` holds the main menu, the loading screen, the pause menu, the settings screen and the
`ScreenHost` that opens screens over the game (the project starts at `ui/menus/menu_scene.tscn`); the options they show
are kept by the `Settings` autoload in `core/settings/`.

`ui/minimap/` is the minimap: `minimap.tscn` (the widget: a round or square map that follows a target, turns, zooms and
draws every `MinimapMarker`), `map_screen.tscn` (the full-screen map, `M`), `map_layer.tscn` (the full-screen map in a
`CanvasLayer`; the small map sits in the HUD's minimap slot) and the pool, projector and baker behind them. Icons
are the template's own white shapes in `assets/ui/minimap/`, tinted by each marker. The kit's
`docs/engines/godot/minimap.md` says how to use and tune it.
