## The pistol's slide rack up close (kit #1081): a mannequin on a `RackStage` (the rack clip, the
## hold's hands, the left hand reached to the slide, the `Slide` node moved), measured by
## `HandContact` on every frame of the clip and filmed at its moments.
##
## Run headless, it prints one `RACK` line a frame: for each hand the deepest part in the weapon
## (or the other hand) and the farthest holding part off it, in millimetres, how far the left
## hand's bone is from its place on the slide, and how far back the slide is (`RACK_PARTS=1` adds
## every part of the left hand). Run with a window and `RACK_OUT=<folder>`, it also saves six
## views of each moment of `MOMENTS` (from the front left, the gun's right, from above, the
## gun's left, a close-up from the player's aim camera and that camera's own view):
## `RACK_OUT=<abs folder> gds godot -- --path game --resolution 1000x800
## res://tools/capture/rack_closeups.tscn`. `MODEL=male` films the male body, `RACK_REACH=0`
## leaves the reach to the slide out (the clip's own arm) and `RACK_FINGERS=0` the body's own
## fingers (the clip's), `RACK_LOCK=0` racks a closed slide (the default is locked back, as the
## game's empty pistol has it, kit #1337), `RACK_ALL=1` films every frame. It lives in
## tools/, which the export leaves out.
extends Node3D

## The moments filmed, in frames (30 a second): the hand over the slide, closed on it (the grip),
## the slide pulled back (the pull), let go with the slide home (the release), and the
## follow-through.
const MOMENTS: Dictionary[String, float] = {
	"reach": 7.0,
	"grip": 9.0,
	"pull": 13.0,
	"release": 15.0,
	"follow": 17.0,
}

var _made: RackStage


func _ready() -> void:
	_light()
	_run.call_deferred("male" if OS.get_environment("MODEL") == "male" else "female")


func _run(model: String) -> void:
	_made = await RackStage.make(self, model)
	_made.reach_on = OS.get_environment("RACK_REACH") != "0"
	_made.fingers_on = OS.get_environment("RACK_FINGERS") != "0"
	_made.lock = 0.0 if OS.get_environment("RACK_LOCK") == "0" else _made.locked_share()
	var out := OS.get_environment("RACK_OUT")
	var film := not out.is_empty() and DisplayServer.get_name() != "headless"
	var camera := Camera3D.new()
	add_child(camera)
	camera.current = true
	for frame in _made.frames() + 1:
		await _pose(float(frame))
		print("RACK %s frame %02d %s" % [model, frame, _measure(float(frame))])
		if film and OS.get_environment("RACK_ALL") == "1":
			await _shoot(camera, out.path_join("%s_frame_%02d" % [model, frame]))
	if film:
		for moment: String in MOMENTS:
			await _pose(MOMENTS[moment])
			await _shoot(camera, out.path_join("%s_%s" % [model, moment]))
	get_tree().quit()


func _pose(frame: float) -> void:
	_made.pose(frame / _made.frames())
	await _made.stage.settle()


func _measure(frame: float) -> String:
	var share := frame / _made.frames()
	var stage := _made.stage
	var right := stage.contact.measure("r")
	var left := stage.contact.measure("l", true)
	var rack := _made.rack
	var contacts := RackStage.SLIDE_CONTACTS
	var where := "on the way"
	if rack.support_weight(share) >= 1.0:
		contacts = HoldStage.LEFT_CONTACTS
		where = "support grip"
	elif rack.is_gripping(share):
		where = "on the slide"
	var line := "| r: " + HandContact.summary(right, HoldStage.RIGHT_CONTACTS)
	line += " | l (%s): %s" % [where, HandContact.summary(left, contacts)]
	if OS.get_environment("RACK_PARTS") == "1":
		var text := PackedStringArray()
		for part: String in left:
			text.append("%s %.1f" % [part, left[part].distance * 1000.0])
		line += " [" + ", ".join(text) + "]"
	line += " | reach %.1f mm" % (_made.reach(share) * 1000.0)
	var pulled := rack.slide_pull(share, _made.lock)
	line += " | slide %.0f mm" % (rack.travel.length() * pulled * 1000.0)
	return line


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


# Six views of the pose: from in front of the character's left, the gun's right, from above (the
# muzzle up the picture), the gun's left from behind and above it (the thumb's side, which is
# toward the chest: nothing nearer than the hands is drawn), a close-up from the player's aim
# camera (1.1 m behind the 1.55 m target, 0.5 m to the right) and that camera's own 50 degree
# view.
func _shoot(camera: Camera3D, path: String) -> void:
	var stage := _made.stage
	var gun := stage.pistol.global_transform.orthonormalized()
	var middle := gun * Vector3(-0.04, 0.07, 0.0)
	var eye := stage.global_transform * Vector3(-0.5, 1.55, -1.1)
	var views := {
		"front": [middle + stage.global_basis * Vector3(0.28, 0.12, 0.45), Vector3.UP, 34.0],
		"right": [middle + gun.basis * Vector3(-0.08, 0.05, -0.5), gun.basis.y, 34.0],
		"top": [middle + gun.basis * Vector3(0.0, 0.5, 0.02), -gun.basis.x, 34.0],
		"left": [middle + gun.basis * Vector3(0.1, 0.16, 0.42), gun.basis.y, 34.0],
		"player": [eye, Vector3.UP, 13.0],
	}
	# The first view after a new pose is taken twice: its first picture still had the camera of
	# the picture before it.
	var order: Array = [views.keys()[0]]
	order.append_array(views.keys())
	for view: String in order:
		# From the sides and above, nothing nearer than the hands is drawn (the chest, the head).
		camera.near = 0.3 if view in ["right", "top", "left"] else 0.02
		camera.fov = views[view][2]
		camera.look_at_from_position(views[view][0], middle, views[view][1])
		for _i in 3:
			await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("%s_%s.png" % [path, view])
	camera.near = 0.02
	camera.fov = 50.0
	camera.look_at_from_position(eye, eye + stage.global_basis.z * 4.0)
	for _i in 3:
		await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s_game.png" % path)
