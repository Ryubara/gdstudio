@tool
class_name WeaponPickup
extends Pickup
## A weapon lying in the level for a character to take, the way arena shooters show one: its model
## floats, turns and bobs over a glowing ring, and a character that walks into it is given the
## weapon (`weapon`, a `WeaponDef`) with `rounds` rounds through its `WeaponLoadout.give()`. One
## that already carries the weapon takes only the rounds; one whose reserve is full leaves it
## where it is. It comes back after `respawn_time` (0: once only).
##
## Everything it shows is a node of `weapon_pickup.tscn`: the weapon's model goes under `Visual`
## (a scene that extends this one, like `rifle_pickup.tscn`, puts it there), `Glow` is the ring on
## the ground and `Light` a small light in the weapon's colour (`tint`, no shadow; ten rifle
## pickups drew 35 draw calls on the Compatibility renderer with their lights and without, but a
## mesh takes at most 8 lights there, so delete it on a level that crowds pickups together).
## `Sound` plays the pickup sound. The spin, the bob, the respawn and the sound are `Pickup`'s.
##
## What a body was given is gameplay (a server decides it); the spin, the glow and the sound are
## cosmetic and never sent.

## A character took the weapon: `given` is `WeaponLoadout.Given.WEAPON` (a new weapon) or `AMMO`
## (only its rounds).
signal weapon_taken(collector: Node3D, definition: WeaponDef, given: WeaponLoadout.Given)

@export_group("Weapon")
## The weapon it gives.
@export var weapon: WeaponDef
## The rounds it gives for the weapon's reserve (beside a full magazine when the weapon is new).
@export_range(0, 999, 1, "or_greater") var rounds := 60


func _get_configuration_warnings() -> PackedStringArray:
	var warnings := super()
	if weapon == null:
		warnings.append("Set `weapon`: the WeaponDef this pickup gives.")
	return warnings


# Gives the weapon (or its rounds) to the body's loadout; false when it has none, or carries the
# weapon with a full reserve.
func _give(body: Node3D) -> bool:
	var loadout := _loadout_of(body)
	if loadout == null or weapon == null:
		return false
	var given := loadout.give(weapon, rounds)
	if given == WeaponLoadout.Given.NOTHING:
		return false
	collected.emit(body, item_id, rounds)
	weapon_taken.emit(body, weapon, given)
	return true


func _set_shown(shown: bool) -> void:
	super(shown)
	for part_name: String in ["Glow", "Light"]:
		var part := get_node_or_null(part_name) as Node3D
		if part != null:
			part.visible = shown


# The tint lights the ring and the light; the model under `Visual` keeps its own colours.
func _update_look() -> void:
	var glow := get_node_or_null("Glow") as MeshInstance3D
	if glow != null and glow.material_override is StandardMaterial3D:
		(glow.material_override as StandardMaterial3D).albedo_color = tint
	var light := get_node_or_null("Light") as OmniLight3D
	if light != null:
		light.light_color = tint


static func _loadout_of(body: Node3D) -> WeaponLoadout:
	var character := body as Character
	if character != null:
		return character.loadout
	for child in body.get_children():
		if child is WeaponLoadout:
			return child
	return null
