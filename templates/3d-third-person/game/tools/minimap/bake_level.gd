## Bakes the level into a top-down PNG for the minimap's image source, then quits.
##
## Run it windowed through the kit (it needs a renderer; the file is written next to the level
## by default, set `MINIMAP_BAKE_OUT` to write somewhere else):
## `gds godot -- --path game res://tools/minimap/bake_level.tscn`
## Then point `Minimap.image` (or a section's `map_texture`) at the PNG and set
## `Minimap.image_world_rect` to `bounds` below. It lives in tools/, which the export leaves out.
extends Node

## The rectangle of the map plane to bake, in metres.
@export var bounds := Rect2(-26.0, -26.0, 52.0, 52.0)
## Pixels to the metre.
@export_range(1.0, 32.0, 1.0) var pixels_per_metre := 8.0
## The camera's height and how far down it draws.
@export var top := 40.0
@export var depth := 60.0
## Where the PNG goes (a `res://` or an absolute path), unless `MINIMAP_BAKE_OUT` says otherwise.
@export var output := "res://world/prototype/prototype_minimap.png"


func _ready() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	var image := await MinimapBaker.bake(self, bounds, pixels_per_metre, top, depth)
	var path := OS.get_environment("MINIMAP_BAKE_OUT")
	if path.is_empty():
		path = output
	var error := image.save_png(path)
	print("BAKED %s (%d x %d) error=%d" % [path, image.get_width(), image.get_height(), error])
	get_tree().quit(error)
