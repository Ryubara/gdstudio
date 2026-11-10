# The minimap

A round map of the world around the character in the top right corner, and a full-screen map on `M`. Both are the
same widget, `ui/minimap/minimap.tscn`, tuned in the inspector; every thing on them is a `MinimapMarker` that a node
carries.

## What is on screen

- The small `Minimap` sits in the HUD's `MinimapSlot` (top right); `MapLayer` (in `main.tscn`) holds the `MapScreen`.
  Nothing else refers to either, so a game that lays its HUD out differently moves or deletes them.
- The small map follows the character, turns with the camera (the way the camera looks is up) and shows the letter N
  where north is. Zoom with `=` and `-` (the actions `map_zoom_in` and `map_zoom_out`).
- `M` (or a pad's Back button, the action `map`) opens the whole map, north up, with every kind of marker; `M` or Esc
  closes it. A map that grows (new `MinimapSection` boxes) is shown whole.

## Putting something on the map

Add a `MinimapMarker` node as a child of any `Node3D` (or `Node2D`) and set its icon, colour and size. The
character, the pickups, the targets and the doors of the template carry one each (`kind` says which). A marker can
stick to the border when its thing is off the map (`clamp_to_edge`), show only near the character, in the same
section or when the game reveals it (`rule`), and fade above or below the character (`height_fade`). A map can leave
a kind out (`hidden_kinds`). Nothing is synced over the network: each player's minimap reads its own scene.

## The map's picture

The live camera (the default) looks straight down from above the character into a small `SubViewport` and draws what is
there: a new section of the map shows up with nothing to set. Put props, characters or roofs on another render layer
and leave that layer out of `live_layers` to keep them off the map. A `MinimapSection` box around a floor or a room
slices the camera to that box while the character is inside it (the workshop's roof does not hide its floor), names the
map and may bring its own picture. For a finished level, bake a picture once (`tools/minimap/bake_level.tscn`), set
`source` to `IMAGE`, and the second render pass is gone.

The numbers (what the live camera, the markers and the rates cost, on the desktop and in a browser) and the full list
of settings are in the kit's `docs/engines/godot/minimap.md`.
