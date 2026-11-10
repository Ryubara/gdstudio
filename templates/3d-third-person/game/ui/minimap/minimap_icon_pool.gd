class_name MinimapIconPool
extends RefCounted
## Hands out `MinimapIcon`s and takes them back. An icon is made only when the free list is empty,
## so after the busiest moment of a level nothing is allocated or freed again.

## The scene each icon is made from.
var scene: PackedScene
## The control the icons are children of.
var parent: Control

var _free: Array[MinimapIcon] = []
var _made := 0
var _in_use := 0


func _init(icon_scene: PackedScene, icon_parent: Control) -> void:
	scene = icon_scene
	parent = icon_parent


## How many icons were ever made.
func made() -> int:
	return _made


## How many icons are out right now.
func in_use() -> int:
	return _in_use


## Makes `count` icons now and keeps them free (so the first busy update allocates nothing).
func prewarm(count: int) -> void:
	var fresh: Array[MinimapIcon] = []
	while _made < count:
		fresh.append(acquire())
	for icon in fresh:
		release(icon)


## An icon from the free list, or a new one.
func acquire() -> MinimapIcon:
	_in_use += 1
	if not _free.is_empty():
		return _free.pop_back()
	var icon := scene.instantiate() as MinimapIcon
	parent.add_child(icon)
	_made += 1
	return icon


## Takes `icon` back: hidden, kept for the next marker.
func release(icon: MinimapIcon) -> void:
	if not is_instance_valid(icon):
		return
	icon.put_away()
	_free.append(icon)
	_in_use -= 1


## Frees every icon (the widget is going away).
func clear() -> void:
	for icon in parent.get_children():
		if icon is MinimapIcon:
			icon.queue_free()
	_free.clear()
	_made = 0
	_in_use = 0
