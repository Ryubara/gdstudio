## The pistol hold study (kit #1001): the mannequin holding the pistol in every pistol clip and in
## the locomotion clips with the pistol out, built by `HoldStage` (the player's own
## `pistol_held.tscn` and hold scene), measured by `HandContact` and filmed up close.
##
## Run headless, it prints one `HOLD` line a pose: for each hand the deepest part in the weapon
## and the farthest holding part off it, in millimetres (`HOLD_PARTS=1` adds every part). Run with
## a window and `HOLD_OUT=<folder>`, it also saves five views of each pose (the gun's left, its
## right, from above, a close-up from the player's aim camera and that camera's own view):
## `HOLD_OUT=<abs folder> gds godot -- --path game --resolution 1000x800
## res://tools/capture/pistol_hold_study.tscn`. `MODEL=male` studies the male mannequin,
## `HOLD_OFF=1` leaves the hold scene out (the clips' own fist), `HOLD_ONLY=reload` studies one
## tag (the reload is filmed at every share of `RELOAD_SHARES`, both hands measured),
## `HOLD_OBJ=<folder>` writes each pose's hands and weapon as an OBJ file. It lives in tools/,
## which the export leaves out.
extends Node3D

## The poses: a tag, the clip, the times sampled, and how far the hold is in its aim.
const POSES: Array[Dictionary] = [
	{"tag": "pistol_idle", "clip": &"ual1/Pistol_Idle", "times": [0.0, 0.5, 1.0]},
	{"tag": "aim_neutral", "clip": &"ual1/Pistol_Aim_Neutral", "times": [0.0, 0.16], "aim": 1.0},
	{"tag": "aim_up", "clip": &"ual1/Pistol_Aim_Up", "times": [0.0, 0.16], "aim": 1.0},
	{"tag": "aim_down", "clip": &"ual1/Pistol_Aim_Down", "times": [0.0, 0.16], "aim": 1.0},
	{"tag": "shoot", "clip": &"ual1/Pistol_Shoot", "times": [0.0, 0.05, 0.1, 0.2], "aim": 1.0},
	{"tag": "reload", "clip": &"ual1/Pistol_Reload", "shares": RELOAD_SHARES},
	{"tag": "carry_idle", "clip": &"ual1/Idle", "times": [0.0, 1.0], "carry": true},
	{"tag": "carry_walk", "clip": &"ual1/Walk", "times": [0.0, 0.3, 0.6], "carry": true},
	{"tag": "carry_jog", "clip": &"ual1/Jog_Fwd", "times": [0.0, 0.25, 0.5], "carry": true},
	{"tag": "carry_sprint", "clip": &"ual1/Sprint", "times": [0.0, 0.2, 0.4], "carry": true},
	{"tag": "carry_crouch", "clip": &"ual1/Crouch_Fwd", "times": [0.0, 0.7], "carry": true},
	{"tag": "carry_jump", "clip": &"ual1/Jump_Start", "times": [0.0], "carry": true},
]

## The shares of the reload that are studied, every one filmed: on the gun, leaving it, at the
## belt, coming back, the magazine going in and seated, and back on the gun.
const RELOAD_SHARES: Array = [
	0.0, 0.04, 0.08, 0.17, 0.25, 0.33, 0.42, 0.5, 0.54, 0.63, 0.71, 0.79, 0.88, 1.0
]

## How near the gun the left view cuts when only the right hand holds it: 7.5 cm off its middle.
const _ONE_HAND_NEAR := 0.425

var _stage: HoldStage


func _ready() -> void:
	_light()
	var model := "male" if OS.get_environment("MODEL") == "male" else "female"
	_stage = HoldStage.make(self, model, OS.get_environment("HOLD_OFF") != "1")
	_run.call_deferred(model)


func _run(model: String) -> void:
	var out := OS.get_environment("HOLD_OUT")
	var film := not out.is_empty() and DisplayServer.get_name() != "headless"
	var camera := Camera3D.new()
	add_child(camera)
	camera.current = true
	camera.near = 0.02
	var only := OS.get_environment("HOLD_ONLY")
	for spec in POSES:
		if only != "" and spec.tag != only:
			continue
		var reload: bool = spec.has("shares")
		var times: Array = spec.shares if reload else spec.times
		for index in times.size():
			var aim: float = spec.get("aim", 0.0)
			if spec.get("carry", false):
				_stage.pose(spec.clip, times[index], aim, &"ual1/Pistol_Idle", [&"hand_r"])
			elif reload:
				var length := _stage.clip(spec.clip).length
				_stage.pose(spec.clip, times[index] * length, aim, &"", [], times[index])
			else:
				_stage.pose(spec.clip, times[index], aim)
			await _stage.settle()
			var tag := "%s_%d" % [spec.tag, index]
			if reload:
				tag = "%s_%03d" % [spec.tag, roundi(times[index] * 100.0)]
			print("HOLD %s %s %s" % [model, tag, _measure(aim > 0.0 or reload)])
			if OS.get_environment("HOLD_OBJ") != "":
				_stage.contact.dump_obj(OS.get_environment("HOLD_OBJ").path_join(tag + ".obj"))
			if film and reload:
				await _shoot(camera, out.path_join(tag), true, true)
			elif film and index == times.size() - 1:
				await _shoot(camera, out.path_join(spec.tag), aim > 0.0)
	get_tree().quit()


func _measure(two_handed: bool) -> String:
	var right := _stage.contact.measure("r")
	var line := "| r: " + HandContact.summary(right, HoldStage.RIGHT_CONTACTS)
	if OS.get_environment("HOLD_PARTS") == "1":
		line += " " + _parts(right)
	if two_handed:
		var left := _stage.contact.measure("l", true)
		line += " | l: " + HandContact.summary(left, HoldStage.LEFT_CONTACTS)
		if OS.get_environment("HOLD_PARTS") == "1":
			line += " " + _parts(left)
		var target := _stage.pistol.get_node_or_null(^"SupportHand") as Node3D
		if target != null:
			var gap := _stage.bone_origin(&"hand_l").distance_to(target.global_position)
			line += " reach %.1f mm" % (gap * 1000.0)
	return line


func _parts(parts: Dictionary) -> String:
	var text := PackedStringArray()
	for part: String in parts:
		text.append("%s %.1f" % [part, parts[part].distance * 1000.0])
	return "[" + ", ".join(text) + "]"


func _light() -> void:
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.36, 0.39, 0.44)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.75, 0.78, 0.85)
	env.environment.ambient_light_energy = 0.8
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 150, 0)
	sun.light_energy = 1.2
	add_child(sun)


# Five views of the pose (six with `under`, from below the grip's foot): the gun's left, its
# right, from above (the muzzle up the picture), a close-up from the player's aim camera (1.1 m
# behind the 1.55 m target, 0.5 m to the right) and that camera's own 50 degree view.
func _shoot(camera: Camera3D, path: String, two_handed: bool, under := false) -> void:
	var gun := _stage.pistol.global_transform.orthonormalized()
	var middle := gun * Vector3(-0.04, 0.03, 0.0)
	var eye := _stage.global_transform * Vector3(-0.5, 1.55, -1.1)
	var views := {
		"left": [middle + gun.basis * Vector3(-0.08, 0.05, 0.5), gun.basis.y, 34.0],
		"right": [middle + gun.basis * Vector3(-0.08, 0.05, -0.5), gun.basis.y, 34.0],
		"top": [middle + gun.basis * Vector3(0.0, 0.5, 0.02), -gun.basis.x, 34.0],
		"player": [eye, Vector3.UP, 13.0],
	}
	if under:
		# From below and ahead of the grip's foot, where a hand at the magazine shows.
		views["under"] = [middle + gun.basis * Vector3(-0.3, -0.33, 0.12), gun.basis.y, 34.0]
	for view: String in views:
		# From the sides and above, nothing nearer than the hands is drawn (a leg, the chest); with
		# one hand on the gun its left is cut closer still, since the thigh is a hand away from it.
		camera.near = 0.02 if view == "player" or view == "under" else 0.3
		if view == "left" and not two_handed:
			camera.near = _ONE_HAND_NEAR
		camera.fov = views[view][2]
		camera.look_at_from_position(views[view][0], middle, views[view][1])
		for _i in 3:
			await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("%s_%s.png" % [path, view])
	camera.near = 0.02
	camera.fov = 50.0
	camera.look_at_from_position(eye, eye + _stage.global_basis.z * 4.0)
	for _i in 3:
		await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s_game.png" % path)
