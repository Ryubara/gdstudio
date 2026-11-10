# ui

Screens, the HUD and their skin: `ui/<area>/` for each (`ui/hud/`, `ui/menus/`), `ui/skin/` for tokens and themes.

- May use everything below it (`core/`, `gameplay/`, `world/`); nothing below uses `ui/`.
- A scene with a script shares its name and folder.

The template has `ui/touch/` (the phone controls, from 3D Blank: a floating stick, a look drag and buttons that press
the game's input actions), `ui/hud/item_counter.tscn` (what the player has collected) and `ui/probe/web_probe.gd` (the
state a browser test reads from the web build when the page is opened with `?probe`).

`ui/minimap/` is the minimap: `minimap.tscn` (the widget: a round or square map that follows a target, turns, zooms and
draws every `MinimapMarker`), `map_screen.tscn` (the full-screen map, `M`), `minimap_layer.tscn` (the two in a
`CanvasLayer`, until the HUD has regions to put them in) and the pool, projector and baker behind them. Icons are the
template's own white shapes in `assets/ui/minimap/`, tinted by each marker. The kit's `docs/engines/godot/minimap.md`
says how to use and tune it.
