@tool
class_name AiFaction
extends Resource
## One side in the `AiRelations` table: its name, its colour and its row of attitudes, how it
## feels about each other faction (-100 hostile to 100 allied). A row is one direction only: this
## faction toward the others, never theirs toward it (the table is asymmetric).

## The name members carry (`AiProfile.faction`, `AiFactionMember.faction`) and events name.
@export var id := &"faction":
	set(value):
		id = value
		emit_changed()
## The colour the debug overlay and a game's UI give the faction.
@export var color := Color(0.8, 0.8, 0.8):
	set(value):
		color = value
		emit_changed()
## Its members may hurt a Friendly or Allied character (a player shooting an ally, and paying for
## it in attitude); off, a shot of theirs at a friend does nothing (`AiFactions.can_hurt`).
@export var hurts_friends := false:
	set(value):
		hurts_friends = value
		emit_changed()
## The base attitude of this faction toward each faction named, -100 to 100; a faction not named
## here is at the table's `default_attitude`. Include its own id (how members treat each other).
@export var attitudes: Dictionary[StringName, int] = {}:
	set(value):
		attitudes = value
		emit_changed()
