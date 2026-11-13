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
## What the head does while the weapon is aimed (`AimHeadModifier`): level and along the aim, or
## brought to the weapon's sights, a cheek on the stock.
enum AimHead { LEVEL, SIGHT }
enum Kind {
	## A body (`projectile_scene`) flies from the muzzle and hits what it touches: it can be seen
	## and dodged, and it costs a physics body while it flies.
	PROJECTILE,
	## One ray from the muzzle, the hit on the tick of the shot, no body: the cheap one, for an
	## automatic weapon, for the web and for a network, where a shot is a small record.
	HITSCAN,
	## The fire button throws the category's melee blow (the empty hands, a blade): a short ray
	## from the chest, `blow_reach()` long, no muzzle, no ammunition. Every weapon has the same
	## blow on the `melee` button.
	MELEE,
}

## What a press of the fire button fires (gdstudio #1352). Every press fires: a tap from the hip
## keeps the arm coming up until its shot (or its burst) has left.
enum FireMode {
	## One shot a press, however long the button is held.
	SINGLE,
	## `burst_size` shots a press, `burst_rate` apart, however short or long the press: a held
	## button fires one burst, and the next press waits one `shot_interval()` after its last shot.
	BURST,
	## Shots at `fire_rate` for as long as the button is held; a tap fires one.
	AUTOMATIC,
}

## The bone from which the free arm keeps the locomotion clip while a `one_handed` weapon aims
## and shoots.
const FREE_ARM_BONE := &"clavicle_l"

@export_group("Weapon")
## The name a HUD or an inventory shows.
@export var display_name := "Weapon"
## The picture a HUD or an inventory shows. Empty: none.
@export var icon: Texture2D
## How a shot travels: a projectile, a hitscan ray or a melee blow. The `hitscan` toggle below
## turns a projectile weapon into a hitscan one without changing this.
@export var kind := Kind.PROJECTILE:
	set(value):
		kind = value
		notify_property_list_changed()

@export_group("Fire")
## What a press fires: one shot, one burst, or shots for as long as it is held. Gameplay: a server
## fires by the same definition, and every shot of a burst is its own small `SHOT` event.
@export var fire_mode := FireMode.SINGLE:
	set(value):
		fire_mode = value
		notify_property_list_changed()
## How many shots (or blows) a second; for a burst weapon, how soon after a burst's last shot the
## next burst may start (one `shot_interval()`).
@export_range(0.5, 30.0, 0.1, "suffix:shots/s") var fire_rate := 4.0
## The shots one press fires, for `FireMode.BURST`.
@export_range(2, 10, 1) var burst_size := 3
## How many shots a second inside a burst, for `FireMode.BURST` (the spacing of its shots).
@export_range(1.0, 30.0, 0.1, "suffix:shots/s") var burst_rate := 15.0
## The shot goes off the aim by up to this angle, picked from the weapon's seeded sequence.
@export_range(0.0, 15.0, 0.1, "suffix:deg") var spread := 0.0
## How hard a shot kicks the player's view: a share of the camera's `shot_kick_amplitude` (1: as
## the camera has it, 2: twice, 0: no kick, as for the fists). The kick is cosmetic and never sent.
@export_range(0.0, 4.0, 0.05) var recoil := 1.0
## What one hit takes from what it hits. The weapon hands it on (`Projectile.damage`, the hit
## record's `damage`); the template's `Target` counts hits, and a game's health reads this.
@export_range(0.0, 1000.0, 0.5, "or_greater") var damage := 34.0
## How far the aim ray looks for something to hit (a hitscan shot reaches `hitscan_range`).
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
## The head while aiming: level and looking along the aim (a pistol, the fists), or with the eye
## brought behind the sights, which tilts the head onto the stock (a shouldered weapon: it needs
## `aim_eye`).
@export var aim_head := AimHead.LEVEL
## Where the aiming eye belongs on the weapon, for `AimHead.SIGHT`: a marker under the character's
## `Model` slot, like `muzzle` (the rifle's `RifleHeld/Pivot/Rifle/AimEye`), its -Z along the sight
## line.
@export var aim_eye: NodePath

@export_group("Aim and zoom")
## What a press of aim or fire does with this weapon in the hands. The character and the camera
## read these every step, so a change while the game runs shows at once. `can_aim` and
## `fire_needs_aim` are gameplay (a server reads them from the same definition); the zoom and the
## crosshair are the local screen's and never sent.
##
## On: the aim button raises the weapon and zooms the view in. Off: the aim button does nothing.
@export var can_aim := true
## On: the fire button shoots only while the aim button is held (with `can_aim` off it never
## does). Off: the fire button aims by itself and shoots once the arm is up.
@export var fire_needs_aim := false
## On: holding fire without aiming zooms the view in (the camera's Fire framing, and the camera's
## `zoom_when_firing` must be on too). Off: firing leaves the framing alone, as for the fists.
@export var fire_zooms := true
## On: the crosshair shows while the player aims or fires with this weapon. Off: never.
@export var show_crosshair := true
@export_subgroup("Zoom")
## On: the zoom below replaces the camera's own aim and fire framing while this weapon is in the
## hands. Off: the camera's `aim_fov`, `aim_distance`, `fire_fov` and `fire_distance` are used.
@export var override_zoom := false
## The field of view while aiming, when `override_zoom` is on.
@export_range(20.0, 110.0, 0.5, "suffix:deg") var aim_fov := 50.0
## How far behind the target the lens sits while aiming, when `override_zoom` is on.
@export_range(0.5, 8.0, 0.05, "suffix:m") var aim_distance := 1.1
## The field of view while firing without aiming, when `override_zoom` is on.
@export_range(20.0, 110.0, 0.5, "suffix:deg") var fire_fov := 56.0
## How far behind the target the lens sits while firing without aiming, when `override_zoom` is on.
@export_range(0.5, 8.0, 0.05, "suffix:m") var fire_distance := 1.4
## Moves the view while zoomed in, when `override_zoom` is on: x further to the side of the chosen
## shoulder (mirrored on the left one), y up. It blends in with the zoom.
@export_custom(PROPERTY_HINT_RANGE, "-1,1,0.01,suffix:m") var zoom_offset := Vector2.ZERO

@export_group("Hitscan")
## On: the weapon fires one instant ray from the aim instead of a projectile (a `PROJECTILE` weapon
## becomes a `HITSCAN` one, `shot_kind()`). Nothing is made for the shot: the muzzle flash, the
## shot sound and the impact where the ray hits are all there is, and online the shot costs only
## its SHOT and HIT events. Read at each shot, so it switches live. No effect on a melee weapon.
@export var hitscan := false:
	set(value):
		hitscan = value
		notify_property_list_changed()
## How far a hitscan shot reaches.
@export_range(5.0, 1000.0, 1.0, "or_greater", "suffix:m") var hitscan_range := 100.0
## What a hitscan shot can hit (physics layers): by default what every shot meets
## (`PhysicsLayers.SHOT_MASK`: the level, characters, props, ragdoll bones and hit zones).
@export_flags_3d_physics var hitscan_mask := PhysicsLayers.SHOT_MASK
## The streak a hitscan shot draws from the muzzle to where its ray ended (a `TracerDef`, drawn
## by the level's `TracerPool` on each screen, never sent). Empty: no tracer, the flash and the
## impact are all there is.
@export var tracer: TracerDef

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
## The kind of weapon it is (the empty hands, a pistol, a rifle: `gameplay/weapon/categories/`):
## its melee blow (the `melee` button, and the fire button of a `Kind.MELEE` weapon) takes the
## category's clips and numbers. Empty: the numbers below, and no clip.
@export var category: WeaponCategory:
	set(value):
		if category != null and category.changed.is_connected(emit_changed):
			category.changed.disconnect(emit_changed)
		category = value
		if category != null:
			category.changed.connect(emit_changed)
		emit_changed()
## On: the blow takes the numbers below instead of its category's (the clips stay the category's).
@export var override_melee := false
## How far a blow reaches from the chest.
@export_range(0.2, 5.0, 0.05, "suffix:m") var melee_reach := 1.1
## What one blow takes, before the hit zone's multiplier.
@export_range(0.0, 1000.0, 0.5, "or_greater") var melee_damage := 15.0
## The push a blow gives (newton seconds).
@export_range(0.0, 500.0, 0.5, "suffix:N·s") var melee_impulse := 25.0
## Seconds from the start of one blow to the start of the next.
@export_range(0.1, 3.0, 0.01, "suffix:s") var melee_cooldown := 0.5
## Seconds after the press the blow can first land, and last land.
@export_range(0.0, 2.0, 0.01, "suffix:s") var melee_hit_start := 0.15
@export_range(0.0, 2.0, 0.01, "suffix:s") var melee_hit_end := 0.25

@export_group("Hold")
## A change to a clip below rebuilds the animation of every character holding the weapon
## (`changed`), so the hold is tuned live.
##
## The node under the character's `Model` slot that is this weapon's model in the hand (the
## pistol's `PistolHeld`); it is shown while the weapon is out and hidden otherwise. Empty: no
## model (fists).
@export var view: NodePath
## The scene of that model in the hand (the rifle's `rifle_held.tscn`), made under the `Model` slot
## the first time a character carries the weapon, named as `view` says, when the slot has no such
## node: a character that never picks the weapon up carries none of its nodes. Empty: the node is
## part of the character's scene (the pistol's `PistolHeld`).
@export var view_scene: PackedScene
## The marker the shots leave from, under the `Model` slot (the pistol's
## `PistolHeld/Pistol/Pistol/Muzzle`). Empty: no muzzle (shots leave from beside the shooter).
@export var muzzle: NodePath
## On: the weapon's clips (grip, aim, reload) are keyed for an upright trunk, the whole upper body
## stood from the pelvis (the rifle's), so they do not play on a lying body: the prone clips keep
## it and the weapon's hold alone carries the weapon there. Off: they play lying too (the pistol's,
## which key the arms).
@export var clips_upright := false
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
## On: the weapon is aimed and shot in one hand (kit #1085): the body side-on, the shooting arm
## out straight, the free arm on the locomotion clip, the shot kicking the wrist and elbow; the
## free hand comes in only for a reload. Off: held in both hands. The character's `WeaponHold`
## has the stance's numbers.
@export var one_handed := false:
	set(value):
		one_handed = value
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
## Aiming while lying down, looking level: a whole upper body made for the ground (the pistol's
## `prone_aim/Prone_Aim_Neutral`, both hands on it over planted elbows). It replaces the aim clips
## above on a lying body. Empty: the lying body aims with the standing clips.
@export var prone_aim_clip: StringName = &"":
	set(value):
		prone_aim_clip = value
		emit_changed()
## Aiming up and down while lying down.
@export var prone_aim_up_clip: StringName = &"":
	set(value):
		prone_aim_up_clip = value
		emit_changed()
@export var prone_aim_down_clip: StringName = &"":
	set(value):
		prone_aim_down_clip = value
		emit_changed()
## The looks the prone down and up clips are made for, in degrees (x down, y up): the aim blends
## between the three by the look and stays on the last one past it.
@export var prone_aim_angles := Vector2(25.0, 20.0):
	set(value):
		prone_aim_angles = value
		emit_changed()
## The clips of a shot (a recoil, a punch), played on the upper body, one after another shot by
## shot (a jab, then a cross). None: a shot plays no clip.
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
## The reload of a lying body, played the same way in place of `reload_clip` while the body lies
## with a prone aim (the pistol's `prone_reload/Prone_Reload_Pistol`: from the prone aim's pose
## and back to it, with the left hand's times of `reload_clip`, which `WeaponHold` follows).
## Empty: a reload lying down shows nothing, since `reload_clip` is made for a standing body.
@export var prone_reload_clip: StringName = &"":
	set(value):
		prone_reload_clip = value
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

## True when the fire mode is `AUTOMATIC`; setting it picks `AUTOMATIC` or `SINGLE`. Kept for code
## written before the fire mode (gdstudio #1352); the inspector shows `fire_mode`.
var automatic: bool:
	get:
		return fire_mode == FireMode.AUTOMATIC
	set(value):
		fire_mode = FireMode.AUTOMATIC if value else FireMode.SINGLE


## How a shot of this weapon travels now: `MELEE` for a melee weapon, `HITSCAN` when `hitscan` is
## on or `kind` says so, else `PROJECTILE`. The weapon reads this, never `kind` alone.
func shot_kind() -> Kind:
	if kind == Kind.MELEE:
		return Kind.MELEE
	if hitscan or kind == Kind.HITSCAN:
		return Kind.HITSCAN
	return Kind.PROJECTILE


## True when a shot is a ray (a hitscan shot or a blow) and makes no projectile.
func shoots_rays() -> bool:
	return shot_kind() != Kind.PROJECTILE


## The physics layers a shot's ray looks in: `hitscan_mask` for a hitscan shot, else `fallback`
## (the weapon's `aim_mask`).
func ray_mask(fallback: int) -> int:
	return hitscan_mask if shot_kind() == Kind.HITSCAN else fallback


## How far a shot's ray reaches: `melee_reach` for a blow, `hitscan_range` for a hitscan shot.
func ray_reach() -> float:
	return melee_reach if shot_kind() == Kind.MELEE else hitscan_range


## True when the weapon uses ammunition (a magazine of at least one round).
func uses_ammo() -> bool:
	return magazine_size > 0


## True when the fire button may shoot (and aim) now, with the aim button held (`aim_held`) or not.
func fire_allowed(aim_held: bool) -> bool:
	return not fire_needs_aim or (can_aim and aim_held)


## The bones whose chains keep the locomotion clip while the weapon aims and shoots: one-handed,
## the free arm from `FREE_ARM_BONE` (it hangs and swings as the body moves; the reload's layer
## still takes it), none in two hands.
func free_bones() -> Array[StringName]:
	return [FREE_ARM_BONE] if one_handed else []


## Seconds between two shots.
func shot_interval() -> float:
	return 1.0 / maxf(fire_rate, 0.001)


## Seconds between two shots of one burst (`burst_rate`).
func burst_interval() -> float:
	return 1.0 / maxf(burst_rate, 0.001)


## The shots one press fires: `burst_size` for a burst weapon, else 1 (an automatic weapon's held
## shots after the first are its trigger held, not the press).
func shots_a_press() -> int:
	return maxi(burst_size, 1) if fire_mode == FireMode.BURST else 1


# The blow's numbers: the category's, or this definition's own when it overrides them or has no
# category (gdstudio #1254). Read them through these, never the fields.
func _melee_source() -> Resource:
	return self if override_melee or category == null else category


## How far the blow reaches from the chest, metres.
func blow_reach() -> float:
	return _melee_source().melee_reach


## What one blow takes, before the hit zone's multiplier.
func blow_damage() -> float:
	return _melee_source().melee_damage


## The push a blow gives, newton seconds.
func blow_impulse() -> float:
	return _melee_source().melee_impulse


## Seconds from one blow's start to the next one's.
func blow_cooldown() -> float:
	return _melee_source().melee_cooldown


## Seconds after the press the blow can first land.
func blow_hit_start() -> float:
	return _melee_source().melee_hit_start


## Seconds after the press the blow can last land (never before it can first land).
func blow_hit_end() -> float:
	return maxf(_melee_source().melee_hit_end, blow_hit_start())


## The blow's clips, one after another blow by blow: the category's (none without one).
func blow_clips() -> Array[StringName]:
	if category == null:
		return [] as Array[StringName]
	return category.melee_clips


## How fast the blow's clips play.
func blow_clip_speed() -> float:
	return category.melee_clip_speed if category != null else 1.0


# The hitscan numbers are read-only in the inspector while the toggle is off (a `HITSCAN` kind
# reads them too).
func _validate_property(property: Dictionary) -> void:
	var field: String = property["name"]
	if field in ["hitscan_range", "hitscan_mask", "tracer"] and shot_kind() != Kind.HITSCAN:
		property["usage"] |= PROPERTY_USAGE_READ_ONLY
	if field in ["burst_size", "burst_rate"] and fire_mode != FireMode.BURST:
		property["usage"] |= PROPERTY_USAGE_READ_ONLY
