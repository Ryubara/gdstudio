## Films the AI section's population (kit #969) from the player's own camera, in the real game.
## `SECTION_TOUR` picks the scenario (the band rings under the feet show the sides: red against
## the player, blue with it):
##
## - `fight` (default, 30 s): the whole population; the player stands at the friendly side and
##   fights whatever is hostile in its sight (`SectionPilot`), the allies join it, the guards and
##   the shooters fight back, the civilians run from the gunfire.
## - `cover` (10 s): a shooter at its post notices the player (who only stands) and fights from
##   cover, peeking.
## - `chase` (14 s): a guard notices the player in front of it, the player runs out of the door,
##   the guard chases after it.
## - `civilians` (8 s): one shot into the floor by the shed's door and the civilians inside run.
##
## The player is invulnerable. Record it with Movie Maker through the kit, from the worktree:
## `SECTION_TOUR=fight gds capture frames --project <game>`
## `--scene res://tools/capture/section_tour.tscn --seconds 30`
## It lives in tools/, which the export leaves out, and nothing in the game refers to it.
extends Node

## The camera's pitch, degrees (looking down a little).
const PITCH := -10.0

var _scenario := "fight"
var _clock := 0.0
var _pilot: SectionPilot
var _section: Node3D
var _spawners: Dictionary[StringName, AiSpawner] = {}

@onready var _main: Node = $Main
@onready var _player: Player = $Main/PlayerRig/Player
@onready var _rig: PlayerCamera = $Main/PlayerRig/PlayerCamera


func _ready() -> void:
	_scenario = (
		OS.get_environment("SECTION_TOUR") if OS.has_environment("SECTION_TOUR") else "fight"
	)
	_section = _main.get_node("World/AISection")
	for spawner: AiSpawner in _section.get_node("Population").get_children():
		spawner.enabled = false
		_spawners[spawner.name] = spawner
	Health.of(_player).invulnerable = true
	(AiFactions.find(_player)).show_bands = true
	match _scenario:
		"cover":
			# North of the tall cover (which hides the post from the middle), west of the window wall.
			_stand(Vector3(-12.0, 0.0, -6.0), -PI / 2.0)
			# The player only stands there, so the shooter's peeks are not cut short by a death.
			_turn_on(&"Shooters", 1, true)
		"chase":
			_stand(Vector3(-6.5, 0.0, -0.5), -PI / 2.0)
			var stops: Array[Node3D] = [_section.get_node("AiMarkers/GuardLane/Stop3")]
			_spawners[&"Grunts"].markers = stops
			_spawners[&"Grunts"].patrol_route = &"hold"
			_turn_on(&"Grunts", 1, true)
		"civilians":
			_stand(Vector3(-9.0, 0.0, 6.5), -PI / 2.0)
			_turn_on(&"Civilians", 3, false)
		_:
			_stand(Vector3(-5.0, 0.0, -1.0), -PI / 2.0)
			for spawner_name: StringName in _spawners:
				_turn_on(spawner_name, _spawners[spawner_name].count, false)
			_fight([Vector3(-5.0, 0.0, -1.0)])


func _physics_process(delta: float) -> void:
	var was := _clock
	_clock += delta
	# The tour's player never runs dry (the clip is of the AI, not of the ammunition).
	var weapon := _player.weapon
	if _pilot != null and weapon.definition != null and int(weapon.reserve) < 12:
		weapon.set_ammo(int(weapon.ammo), weapon.definition.start_reserve)
	match _scenario:
		"chase":
			_chase_step(was)
		"civilians":
			_civilians_step(was)


# The player stands at `spot` (the section's space) facing `heading`, the camera behind it.
func _stand(spot: Vector3, heading: float) -> void:
	_player.teleport(_section.to_global(spot), heading)
	_rig.yaw = rad_to_deg(heading) + 180.0
	_rig.pitch = -PITCH


func _turn_on(spawner_name: StringName, count: int, debug: bool) -> void:
	var spawner := _spawners[spawner_name]
	spawner.count = count
	spawner.debug = debug
	spawner.awake = true
	spawner.enabled = true


func _fight(loop: Array[Vector3]) -> void:
	_pilot = SectionPilot.new()
	_pilot.player = _player
	_pilot.camera_rig = _rig
	var points := PackedVector3Array()
	for point in loop:
		points.append(_section.to_global(point))
	_pilot.waypoints = points
	add_child(_pilot)


# The guard sees the player; at 3 s the player turns and runs out of the door, steps aside out of
# the guard's sight beside the doorway and looks back in; the guard chases.
func _chase_step(was: float) -> void:
	if _crossed(was, 3.0):
		_rig.yaw += 180.0
		Input.action_press(&"move_forward")
		Input.action_press(&"sprint")
	if _crossed(was, 4.6):
		Input.action_release(&"move_forward")
		Input.action_release(&"sprint")
		Input.action_press(&"move_left")
	if _crossed(was, 5.6):
		Input.action_release(&"move_left")
		_rig.yaw -= 150.0


# A shot into the floor in front of the shed's door at 2 s.
func _civilians_step(was: float) -> void:
	if _crossed(was, 1.2):
		_rig.pitch = 30.0
		Input.action_press(&"aim")
	if _crossed(was, 1.6):
		Input.action_press(&"fire")
	if _crossed(was, 1.7):
		Input.action_release(&"fire")
	if _crossed(was, 2.3):
		Input.action_release(&"aim")
		_rig.pitch = -PITCH


func _crossed(was: float, at: float) -> bool:
	return was < at and _clock >= at
