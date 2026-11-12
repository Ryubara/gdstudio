@tool
class_name WeaponCategory
extends Resource
## What every weapon of one kind shares (gdstudio #1254): the empty hands, the pistols, the
## rifles. Today it is the melee blow: its clips, reach, damage, push, cooldown and the window in
## which it lands. A `WeaponDef` names its category (`WeaponDef.category`) and takes these numbers
## unless it overrides them (`WeaponDef.override_melee`). A new category is a new `.tres` of this
## class in `gameplay/weapon/categories/`; nothing else changes.
##
## Every number is read when a blow starts (the cooldown) or on the tick it may land (reach,
## damage, push), so a change while the game runs shows on the next blow. A change to a clip
## rebuilds the animation of every character holding a weapon of the category (`changed`).

@export_group("Category")
## The name a HUD or a debug view shows.
@export var display_name := "Category"

@export_group("Melee")
## The blow's clips, played on the upper body one after another, blow by blow (a jab, a cross, a
## hook). Empty: the blow lands with no clip.
@export var melee_clips: Array[StringName] = []:
	set(value):
		melee_clips = value
		emit_changed()
## How fast the clips play (1 is their own speed). The hit window below is in game seconds, so a
## faster clip wants an earlier window.
@export_range(0.25, 4.0, 0.05) var melee_clip_speed := 1.0:
	set(value):
		melee_clip_speed = value
		emit_changed()
## How far the blow reaches from the chest, along the aim.
@export_range(0.2, 5.0, 0.05, "suffix:m") var melee_reach := 1.1
## What one blow takes from what it hits, before the hit zone's multiplier.
@export_range(0.0, 1000.0, 0.5, "or_greater") var melee_damage := 15.0
## The push a blow gives a physics body or a ragdoll (newton seconds).
@export_range(0.0, 500.0, 0.5, "suffix:N·s") var melee_impulse := 25.0
## Seconds from the start of one blow to the start of the next. The weapon does not fire, reload
## or switch-fire during it.
@export_range(0.1, 3.0, 0.01, "suffix:s") var melee_cooldown := 0.5
## Seconds after the press the blow can first land (the fist or the gun reaching out in the clip).
@export_range(0.0, 2.0, 0.01, "suffix:s") var melee_hit_start := 0.15
## Seconds after the press the blow can last land. It lands once, on the first tick of the window
## its ray meets something; a window with nothing in reach is a miss.
@export_range(0.0, 2.0, 0.01, "suffix:s") var melee_hit_end := 0.25

@export_group("Sound")
## The swing (an `AudioStreamRandomizer` gives a spread of takes). Empty: silent.
@export var melee_sound: AudioStream
## Its loudness.
@export_range(-60.0, 12.0, 0.5, "suffix:dB") var melee_volume_db := -27.0
