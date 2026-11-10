## Stills of the two map sections from the player's camera, for a pull request (kit #885): the
## character stands at each spot (`teleport`) and the camera turns with the same `yaw` and `pitch`
## the mouse sets; then a few views from above. Each still is saved as a PNG in `SHOT_DIR`.
##
## Run it windowed through the kit, on the web's renderer, with `SHOT_DIR` set:
## `gds godot -- --path game --rendering-method gl_compatibility`
## `res://tools/capture/sections_tour.tscn`. `--debug-navigation` draws the baked
## navigation meshes in the views from above. It lives in tools/, which the export
## leaves out, and nothing in the game refers to it.
extends Node

## Frames a view is given to settle before it is saved.
const SETTLE := 45
## The stills: a name, where the character stands, the camera's yaw (degrees, 0 looks along -Z,
## 90 along -X) and pitch; or, with `above`, a camera of its own at a place looking at a point.
const SHOTS: Array[Dictionary] = [
	{"name": "01_main_to_ai_doorway", "at": Vector3(-12, 0, -9), "yaw": 90.0, "pitch": 8.0},
	{"name": "02_ai_doorway", "at": Vector3(-22.5, 0, -9), "yaw": 90.0, "pitch": 8.0},
	{"name": "03_ai_from_entry", "at": Vector3(-28, 0, -9), "yaw": 90.0, "pitch": 6.0},
	{"name": "04_ai_from_enemy_side", "at": Vector3(-52, 0, -13), "yaw": -90.0, "pitch": 8.0},
	{"name": "05_ai_shed_inside", "at": Vector3(-43.5, 0, -2.5), "yaw": -90.0, "pitch": 6.0},
	{"name": "06_ai_window", "at": Vector3(-31, 0, -18), "yaw": 90.0, "pitch": 2.0},
	{"name": "07_main_to_pathing_doorway", "at": Vector3(10, 0, -6.5), "yaw": -90.0, "pitch": 8.0},
	{"name": "08_pathing_from_entry", "at": Vector3(28, 0, -6), "yaw": -90.0, "pitch": 6.0},
	{"name": "09_pathing_passages", "at": Vector3(35, 0, 0), "yaw": -90.0, "pitch": 6.0},
	{"name": "10_pathing_heights", "at": Vector3(43, 0, 9), "yaw": -90.0, "pitch": 10.0},
	{"name": "11_pathing_door", "at": Vector3(35, 0, -17), "yaw": -90.0, "pitch": 6.0},
	{"name": "12_pathing_movers", "at": Vector3(28, 0, -9), "yaw": 0.0, "pitch": 10.0},
	{"name": "13_pathing_gap_from_deck", "at": Vector3(54, 1.6, 2), "yaw": -90.0, "pitch": 12.0},
	{"name": "14_ai_from_above", "above": Vector3(-42, 42, 8), "look": Vector3(-42, 0, -9)},
	{"name": "15_pathing_from_above", "above": Vector3(45, 48, 14), "look": Vector3(45, 0, -4)},
	{"name": "16_map_from_above", "above": Vector3(0, 95, 45), "look": Vector3(0, 0, -4)},
]

@onready var _player: Player = $Main/PlayerRig/Player
@onready var _rig: PlayerCamera = $Main/PlayerRig/PlayerCamera
@onready var _above: Camera3D = $Above


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var folder := OS.get_environment("SHOT_DIR")
	await _frames(30)
	for shot in SHOTS:
		if shot.has("above"):
			_above.position = shot["above"]
			_above.look_at(shot["look"])
			_above.make_current()
		else:
			($Main/PlayerRig/Camera as Camera3D).make_current()
			_player.teleport(shot["at"], deg_to_rad(shot["yaw"]) + PI)
			_rig.yaw = shot["yaw"]
			_rig.pitch = shot["pitch"]
		await _frames(SETTLE)
		await RenderingServer.frame_post_draw
		if not folder.is_empty():
			var image := get_viewport().get_texture().get_image()
			image.save_png(folder.path_join(shot["name"] + ".png"))
		print("SHOT ", shot["name"])
	get_tree().quit()


func _frames(count: int) -> void:
	for _frame in count:
		await get_tree().process_frame
