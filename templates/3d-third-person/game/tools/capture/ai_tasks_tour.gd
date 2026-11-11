## Films the task layers of one AI character from the player's own camera, with the debug overlay
## on (the layer stack above the head, the active task marked): a grunt patrols between two
## points (a ROUTINE repeat of walk, wait, walk, wait); a noise goes off behind it, a RESPONSE
## investigate suspends the patrol, walks to the noise and waits there; when it ends the patrol
## resumes on the leg it was on, not from its start.
##
## Record it with Movie Maker through the kit:
## `gds capture frames --project game --scene res://tools/capture/ai_tasks_tour.tscn --seconds 13`
## It lives in tools/, which the export leaves out, and nothing in the game refers to it.
extends Node

const CHARACTER := "res://gameplay/ai/ai_character.tscn"
## Where the player stands (looking along -Z), the patrol's two ends and the noise.
const STAND := Vector3(-1.8, 0.0, 17.5)
const PATROL_A := Vector3(-7.5, 0.0, 12.0)
const PATROL_B := Vector3(-3.8, 0.0, 12.0)
const NOISE := Vector3(-4.6, 0.0, 14.8)
## Seconds into the clip of each beat.
const NOISE_AT := 3.1
const NOISE_SHOWN := 1.6
const END := 11.5
## Camera pitch, in degrees, while filming.
const PITCH := 6.0
## The share of a full push of a patrol walk.
const WALK_STRENGTH := 0.6

var _clock := 0.0
var _grunt: AiCharacter
var _marker: MeshInstance3D

@onready var _player: Player = $Main/PlayerRig/Player
@onready var _rig: PlayerCamera = $Main/PlayerRig/PlayerCamera


## Walks to `goal` on the movement channel and succeeds there (the tour's stand-in for the stock
## go-to of gdstudio #968).
class TourWalk:
	extends AiTask

	func update(_delta: float) -> Status:
		var body := character as Node3D
		var to := goal - body.global_position
		to.y = 0.0
		if to.length() < 0.35:
			controller.walk_direction = Vector3.ZERO
			return Status.SUCCEEDED
		controller.walk_direction = to.normalized()
		controller.walk_strength = WALK_STRENGTH
		return Status.RUNNING


## Stands still for `seconds`.
class TourWait:
	extends AiTask
	var seconds := 1.0

	func update(_delta: float) -> Status:
		return Status.SUCCEEDED if elapsed >= seconds else Status.RUNNING


func _ready() -> void:
	_player.teleport(STAND, PI)
	_grunt = (load(CHARACTER) as PackedScene).instantiate() as AiCharacter
	_grunt.debug = true
	_player.get_parent().add_child(_grunt)
	_grunt.teleport(PATROL_A, 0.0)
	(_grunt.task_runner as AiTasks).runner.assign(_patrol(), &"tour")
	_marker = _noise_marker()
	add_child(_marker)


func _physics_process(delta: float) -> void:
	var was := _clock
	_clock += delta
	_face()
	if _crossed(was, NOISE_AT):
		_marker.global_position = NOISE + Vector3.UP * 0.3
		_marker.visible = true
		_grunt.situation.request(AiSituation.Situation.SUSPICIOUS)
		(_grunt.task_runner as AiTasks).runner.assign(_investigate(), &"noise")
	if _crossed(was, NOISE_AT + NOISE_SHOWN):
		_marker.visible = false
	if _crossed(was, END):
		_finish()


func _patrol() -> AiTask:
	var route := AiTaskSequence.new()
	route.id = &"route"
	route.children = [
		_walk(&"walk_to_b", PATROL_B), _wait(1.0), _walk(&"walk_to_a", PATROL_A), _wait(1.0)
	]
	var patrol := AiTaskRepeat.new()
	patrol.id = &"patrol"
	patrol.layer = AiTask.Layer.ROUTINE
	patrol.children = [route]
	return patrol


func _investigate() -> AiTask:
	var go := _walk(&"go_to_noise", NOISE)
	var look := _wait(1.6)
	var investigate := AiTaskSequence.new()
	investigate.id = &"investigate"
	investigate.layer = AiTask.Layer.RESPONSE
	investigate.children = [go, look]
	return investigate


func _walk(task_id: StringName, to: Vector3) -> AiTask:
	var walk := TourWalk.new()
	walk.id = task_id
	walk.goal = to
	return walk


func _wait(seconds: float) -> AiTask:
	var wait := TourWait.new()
	wait.id = &"wait"
	wait.seconds = seconds
	wait.channels = 0
	return wait


func _noise_marker() -> MeshInstance3D:
	var mesh := SphereMesh.new()
	mesh.radius = 0.18
	mesh.height = 0.36
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(1.0, 0.75, 0.2)
	material.emission_enabled = true
	material.emission = Color(1.0, 0.6, 0.1)
	material.emission_energy_multiplier = 3.0
	mesh.material = material
	var marker := MeshInstance3D.new()
	marker.mesh = mesh
	marker.visible = false
	return marker


func _crossed(was: float, at: float) -> bool:
	return was < at and _clock >= at


# Stops the sounds and gives the mixer a few frames to let go of them before the capture quits
# (a voice still playing at exit is reported as a leak).
func _finish() -> void:
	set_physics_process(false)
	AudioSettings.stop_players(get_tree().root)
	for _frame in 8:
		await get_tree().process_frame
	get_tree().quit()


# Holds the camera along -Z at a small pitch, a few degrees a frame.
func _face() -> void:
	var by_yaw := clampf(wrapf(0.0 - _rig.yaw, -180.0, 180.0), -6.0, 6.0)
	var by_pitch := clampf(PITCH - _rig.pitch, -2.0, 2.0)
	_rig.orbit(Vector2(-by_yaw, by_pitch))
