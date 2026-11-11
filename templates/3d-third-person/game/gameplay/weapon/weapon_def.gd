@tool
class_name WeaponDef
extends Resource
## One kind of weapon as data: its name and icon, how a shot travels, its numbers (rate, spread,
## damage, magazine, reserve, reload), its projectile, how a character holds it (the model node it
## shows and the clips it plays) and its sounds. A new weapon is a new `.tres` of this class: a
## `Weapon` node fires whichever definition it is given (`Weapon.definition`), and a
## `WeaponLoadout` switches between several. Compare and list weapons by their definitions.
##
## A `Weapon` reads the numbers when it fires and when it reloads, so a change while the game runs
## shows in the next shot. The definition is shared by every weapon that holds it (a `.tres` is
## loaded once): to change one character's weapon alone, give it a copy (`duplicate()`).

## What a character does when it aims past what its move lets the upper body reach.
enum PastAimLimit {
	## The body turns, so the aim is within reach.
	TURN_BODY,
	## The body keeps its way and the trigger does nothing until the aim is within reach.
	REFUSE_SHOT,
}

## How a shot travels.
enum Kind {
	## A body (`projectile_scene`) flies from the muzzle and hits what it touches: it can be seen
	## and dodged, and it costs a physics body while it flies.
	PROJECTILE,
	## One ray from the muzzle, the hit on the tick of the shot, no body: the cheap one, for an
	## automatic weapon, for the web and for a network, where a shot is a small record.
	HITSCAN,
	## A short ray from the character's chest, `melee_reach` long (fists, a blade): no muzzle, no
	## ammunition.
	MELEE,
}

@export_group("Weapon")
## The name a HUD or an inventory shows.
@export var display_name := "Weapon"
## The picture a HUD or an inventory shows. Empty: none.
@export var icon: Texture2D
## How a shot travels: a projectile, a hitscan ray or a melee blow.
@export var kind := Kind.PROJECTILE

@export_group("Fire")
## On: holding the fire button keeps shooting. Off: one shot a press.
@export var automatic := false
## How many shots (or blows) a second.
@export_range(0.5, 30.0, 0.1, "suffix:shots/s") var fire_rate := 4.0
## The shot goes off the aim by up to this angle, picked from the weapon's seeded sequence.
@export_range(0.0, 15.0, 0.1, "suffix:deg") var spread := 0.0
## How hard a shot kicks the player's view: a share of the camera's `shot_kick_amplitude` (1: as
## the camera has it, 2: twice, 0: no kick, as for the fists). The kick is cosmetic and never sent.
@export_range(0.0, 4.0, 0.05) var recoil := 1.0
## What one hit takes from what it hits. The weapon hands it on (`Projectile.damage`, the hit
## record's `damage`); the template's `Target` counts hits, and a game's health reads this.
@export_range(0.0, 1000.0, 0.5, "or_greater") var damage := 34.0
## How far the aim ray (and a hitscan shot) looks for something to hit.
@export_range(5.0, 500.0, 1.0, "suffix:m") var aim_range := 100.0
## The push a hit gives a physics body (newton seconds).
@export_range(0.0, 500.0, 0.5, "suffix:N·s") var impulse := 40.0
## On: hits leave marks, effects and sounds (the level's `Impacts`). Off: they land unseen.
@export var impacts := true

@export_group("Aim")
## What happens when the character aims past the reach of its move's `AimLimits` (a slide keeps
## the body along the slide): the body turns so the aim is within reach again, or the shot is
## refused until it is.
@export var past_aim_limit := PastAimLimit.TURN_BODY

@export_group("Ammo")
## Rounds in a full magazine. Zero: the weapon needs no ammunition (fists, a blade) and shows no
## ammo on the HUD.
@export_range(0, 200, 1, "or_greater") var magazine_size := 12
## Rounds the weapon is given beside its full magazine.
@export_range(0, 999, 1, "or_greater") var start_reserve := 36
## The most rounds the reserve holds; ammunition picked up past it is left.
@export_range(0, 999, 1, "or_greater") var max_reserve := 96
## The `Pickup.item_id` that fills this weapon's reserve. Empty: nothing does.
@export var ammo_item: StringName = &""
## Seconds from the start of a reload to the rounds going in (they go in at its end, never at its
## start, so a reload cut short by a switch gives nothing).
@export_range(0.1, 10.0, 0.05, "suffix:s") var reload_time := 1.6
## On: an empty magazine with rounds in reserve reloads by itself (a phone that holds fire needs
## it). Off: only the reload button reloads, and a pull of the empty trigger clicks.
@export var auto_reload := true

@export_group("Switch")
## Seconds to put the weapon away before the next one comes out.
@export_range(0.0, 3.0, 0.01, "suffix:s") var holster_time := 0.2
## Seconds to bring it out, ready to shoot at the end.
@export_range(0.0, 3.0, 0.01, "suffix:s") var draw_time := 0.25

@export_group("Projectile")
## The body made for each shot (`Kind.PROJECTILE`).
@export var projectile_scene: PackedScene
## How fast it flies.
@export_range(5.0, 200.0, 0.5, "suffix:m/s") var projectile_speed := 45.0
## Its diameter.
@export_range(0.02, 1.0, 0.01, "suffix:m") var projectile_size := 0.14
## Its colour (it glows). Every projectile of one colour shares one material.
@export var projectile_tint := Color(1.0, 0.85, 0.35)
## How fast it falls; zero flies straight at the crosshair.
@export_range(0.0, 30.0, 0.1, "suffix:m/s²") var projectile_gravity := 0.0
## It disappears this long after it was fired.
@export_range(0.2, 20.0, 0.1, "suffix:s") var projectile_lifetime := 3.0
## How many times it bounces off the level before it stops.
@export_range(0, 8, 1) var projectile_bounces := 0
## The share of its speed a bounce keeps.
@export_range(0.0, 1.0, 0.01) var projectile_bounce_keep := 0.6

@export_group("Melee")
## How far a blow reaches from the chest (`Kind.MELEE`).
@export_range(0.2, 5.0, 0.05, "suffix:m") var melee_reach := 1.1

@export_group("Hold")
## A change to a clip below rebuilds the animation of every character holding the weapon
## (`changed`), so the hold is tuned live.
##
## The node under the character's `Model` slot that is this weapon's model in the hand (the
## pistol's `PistolHeld`); it is shown while the weapon is out and hidden otherwise. Empty: no
## model (fists).
@export var view: NodePath
## The marker the shots leave from, under the `Model` slot (the pistol's
## `PistolHeld/Pistol/Pistol/Muzzle`). Empty: no muzzle (shots leave from beside the shooter).
@export var muzzle: NodePath
## The clip whose pose the gripping hand takes while the weapon is out. Empty: no grip pose
## (the arms follow the locomotion).
@export var grip_clip: StringName = &"":
	set(value):
		grip_clip = value
		emit_changed()
## The bones that take the grip pose (each with every bone below it).
@export var grip_bones: Array[StringName] = [&"hand_r"]:
	set(value):
		grip_bones = value
		emit_changed()
## Aiming level; the aim blends to the clips below by how far up or down the character looks.
## Empty: no aim pose (the arms stay as they are while aiming).
@export var aim_clip: StringName = &"":
	set(value):
		aim_clip = value
		emit_changed()
## Aiming up.
@export var aim_up_clip: StringName = &"":
	set(value):
		aim_up_clip = value
		emit_changed()
## Aiming down.
@export var aim_down_clip: StringName = &"":
	set(value):
		aim_down_clip = value
		emit_changed()
## The clips of a shot (a recoil, a punch), played on the upper body, one after another shot by
## shot (a jab, then a cross).
@export var shoot_clips: Array[StringName] = []:
	set(value):
		shoot_clips = value
		emit_changed()
## On: a shot's clip is added to the pose under it as its difference from its own first frame (the
## first frame is the aim pose it was made on), so the recoil rocks the body wherever the character
## aims, up and down too (the pistol, the rifle). Off: the clip replaces the pose under it while it
## plays (a punch).
@export var shoot_additive := false:
	set(value):
		shoot_additive = value
		emit_changed()
## The reload, played on the upper body and stretched to `reload_time`. Empty: none.
@export var reload_clip: StringName = &"":
	set(value):
		reload_clip = value
		emit_changed()

@export_group("Sound")
## A shot (an `AudioStreamRandomizer` gives a spread of takes).
@export var shot_sound: AudioStream
## Its loudness.
@export_range(-60.0, 12.0, 0.5, "suffix:dB") var shot_volume_db := -22.0
## The click of a pull on an empty magazine.
@export var empty_sound: AudioStream
## The steps of a reload, in order (a magazine out, one in, the slide), each played at its share of
## `reload_time` in `reload_sound_at`.
@export var reload_sounds: Array[AudioStream] = []
## When each reload sound plays, as shares of `reload_time` (0 at the start, 1 at the end).
@export var reload_sound_at: PackedFloat32Array = PackedFloat32Array()
## The weapon coming out.
@export var draw_sound: AudioStream

@export_group("Muzzle flash")
## What flashes at the muzzle (an `EffectDef` the level's `EffectEmitter` plays). Empty: none.
@export_custom(PROPERTY_HINT_RESOURCE_TYPE, "EffectDef") var muzzle_flash: Resource
## Makes the flash bigger or smaller (its particles and the reach of its light).
@export_range(0.1, 4.0, 0.05, "or_greater", "suffix:x") var muzzle_flash_size := 1.0


## True when the weapon uses ammunition (a magazine of at least one round).
func uses_ammo() -> bool:
	return magazine_size > 0


## Seconds between two shots.
func shot_interval() -> float:
	return 1.0 / maxf(fire_rate, 0.001)
