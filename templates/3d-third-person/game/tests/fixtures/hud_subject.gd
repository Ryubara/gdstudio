class_name HudSubject
extends Node
## A stand-in for a player that has what the HUD's health and ammo parts read, for the suites:
## `health` and `max_health` (null until a test sets them), a `weapon` with `ammo` and
## `magazine_size`, and the signals the parts listen to. The real player has none of these yet.

signal health_changed(health: float)
signal took_hit(amount: float, source: Node3D)
signal died
signal revived
signal item_collected(item_id: StringName, amount: int, total: int)
signal aim_changed(aiming: bool)

var health: Variant = null
var max_health: Variant = null
var items: Dictionary = {}
var aiming := false
var weapon: HudSubjectWeapon


## Gives it health and tells the HUD, as the hit zones' damage will.
func set_health(value: float, largest: float = 100.0) -> void:
	max_health = largest
	health = value
	health_changed.emit(value)
