class_name HudSubjectWeapon
extends Node
## The weapon of a `HudSubject`: a magazine and its signal.

signal ammo_changed(ammo: int)
signal fired(shot: Node)

var ammo: Variant = null
var magazine_size: Variant = null


func set_ammo(value: int, size: int = 12) -> void:
	magazine_size = size
	ammo = value
	ammo_changed.emit(value)
