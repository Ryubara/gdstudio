extends Node3D
## Rig-sharing spike: one AnimationLibrary ("rig") with the zombie's Walk and the Soldier's Run, played on both.
##
##   godot --path sandbox/rig-sharing/godot -- --out <dir>
##
## Prints measurements (prefixed RIG:) and writes <dir>/sheet.png: a row per clip, four moments of each, both
## characters playing the same clip from the same library. Quits when done.

const CLIPS := [["Walk", "zombie"], ["Run", "soldier"], ["Walk_NoPos", "zombie"], ["Run_NoPos", "soldier"], ["Walk_Rebased", "zombie"], ["Run_Rebased", "soldier"]]
const SAMPLES := 4
const CELL := Vector2i(640, 400)

var out_dir := "user://"


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var i := args.find("--out")
	if i >= 0 and i + 1 < args.size():
		out_dir = args[i + 1]

	var soldier := _spawn("res://models/soldier.glb", Vector3(-0.55, 0, 0))
	var zombie := _spawn("res://models/zombie.glb", Vector3(0.55, 0, 0))
	var players := {"soldier": _player(soldier), "zombie": _player(zombie)}
	var skels := {"soldier": _skeleton(soldier), "zombie": _skeleton(zombie)}

	for who in skels:
		var sk: Skeleton3D = skels[who]
		var rests := []
		for b in ["Root", "Body", "Hips", "Abdomen", "UpperLeg.L"]:
			rests.append("%s%s" % [b, sk.get_bone_rest(sk.find_bone(b)).origin])
		print("RIG: %s bones=%d rest=%s skeleton_path=%s clips=%s" % [
			who, sk.get_bone_count(), rests, soldier.get_path_to(sk) if who == "soldier"
			else zombie.get_path_to(sk), players[who].get_animation_list()])

	# One library, clips taken from whichever file has them.
	var lib := AnimationLibrary.new()
	for c in CLIPS:
		var src: String = c[0].trim_suffix("_NoPos").trim_suffix("_Rebased")
		var anim: Animation = players[c[1]].get_animation(src).duplicate(true)
		anim.loop_mode = Animation.LOOP_LINEAR
		if c[0].ends_with("_NoPos"):
			# Bone position tracks are absolute: they carry the source character's rest offsets (Body sits 0.32 m
			# lower in the zombie than in the Soldier). Without them a clip is rotations only and fits any body.
			for t in range(anim.get_track_count() - 1, -1, -1):
				if anim.track_get_type(t) == Animation.TYPE_POSITION_3D:
					anim.remove_track(t)
		if c[0].ends_with("_Rebased"):
			# Remember the source's rest position of every bone the clip moves; retarget_player.gd rebases them.
			var sk: Skeleton3D = skels[c[1]]
			var rest := {}
			for t in anim.get_track_count():
				if anim.track_get_type(t) == Animation.TYPE_POSITION_3D:
					var bone := String(anim.track_get_path(t).get_concatenated_subnames())
					rest[bone] = sk.get_bone_rest(sk.find_bone(bone)).origin
			anim.set_meta("src_rest", rest)
		lib.add_animation(c[0], anim)
		_report_tracks(c[0], c[1], anim, skels)
	for who in players:
		players[who].set_script(preload("res://retarget_player.gd"))
		players[who].add_animation_library("rig", lib)
	ResourceSaver.save(lib, out_dir.path_join("rig_library.tres"))

	_report_raw()
	await _capture(players)
	get_tree().quit()


func _spawn(path: String, at: Vector3) -> Node3D:
	var n: Node3D = load(path).instantiate()
	n.position = at
	add_child(n)
	return n


func _player(n: Node) -> AnimationPlayer:
	return n.find_children("*", "AnimationPlayer", true, false)[0]


func _skeleton(n: Node) -> Skeleton3D:
	return n.find_children("*", "Skeleton3D", true, false)[0]


## Which tracks of a clip resolve on each character, and whether the clip carries root motion.
func _report_tracks(clip: String, src: String, anim: Animation, skels: Dictionary) -> void:
	var kinds := {}
	for t in anim.get_track_count():
		var k := anim.track_get_type(t)
		kinds[k] = kinds.get(k, 0) + 1
	print("RIG: clip %s (from %s) length=%.3f tracks=%d by_type=%s first_path=%s" % [
		clip, src, anim.length, anim.get_track_count(), kinds, anim.track_get_path(0)])
	for who in skels:
		var sk: Skeleton3D = skels[who]
		var missing := []
		for t in anim.get_track_count():
			var bone := String(anim.track_get_path(t).get_concatenated_subnames())
			if bone != "" and sk.find_bone(bone) < 0:
				missing.append(bone)
		print("RIG:   on %s: %d tracks name a bone it does not have %s" % [who, missing.size(), missing])
	for bone in ["Root", "Body", "Hips"]:
		var t := anim.find_track(NodePath("CharacterArmature/Skeleton3D:" + bone), Animation.TYPE_POSITION_3D)
		if t >= 0:
			var a: Vector3 = anim.track_get_key_value(t, 0)
			var b: Vector3 = anim.track_get_key_value(t, anim.track_get_key_count(t) - 1)
			var lo := a
			var hi := a
			for k in anim.track_get_key_count(t):
				var v: Vector3 = anim.track_get_key_value(t, k)
				lo = lo.min(v)
				hi = hi.max(v)
			print("RIG:   %s position first=%s last=%s range=%s" % [bone, a, b, hi - lo])
		else:
			print("RIG:   %s has no position track" % bone)


## The uncleaned zombie, as Quaternius ships it: where its skeleton sits and what its tracks are called.
func _report_raw() -> void:
	var raw: Node3D = load("res://raw/zombie_raw.glb").instantiate()
	add_child(raw)
	var sk := _skeleton(raw)
	var p := _player(raw)
	var walk_name := ""
	for n in p.get_animation_list():
		if n.ends_with("Walk"):
			walk_name = n
			break
	var walk := p.get_animation(walk_name)
	print("RIG: raw zombie skeleton_path=%s skeleton_global_scale=%s clips=%d walk=%s first_path=%s hips_rest=%s" % [
		raw.get_path_to(sk), sk.global_transform.basis.get_scale(), p.get_animation_list().size(), walk_name,
		walk.track_get_path(0), sk.get_bone_rest(sk.find_bone("Hips")).origin])
	raw.queue_free()


func _capture(players: Dictionary) -> void:
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 2.6
	cam.position = Vector3(0, 0.95, 6)
	add_child(cam)
	cam.make_current()
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, 25, 0)
	add_child(sun)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.82, 0.82, 0.8)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.6, 0.6, 0.6)
	add_child(env)
	var label := Label3D.new()
	label.position = Vector3(0, 2.05, 0)
	label.font_size = 32
	label.pixel_size = 0.004
	label.modulate = Color.BLACK
	label.outline_size = 0
	add_child(label)
	var ground := MeshInstance3D.new()
	var plane := BoxMesh.new()
	plane.size = Vector3(3.0, 0.01, 0.05)
	ground.mesh = plane
	ground.position = Vector3(0, -0.005, 0)
	add_child(ground)

	var sheet := Image.create(CELL.x * SAMPLES, CELL.y * CLIPS.size(), false, Image.FORMAT_RGB8)
	for row in CLIPS.size():
		var clip: String = CLIPS[row][0]
		for col in SAMPLES:
			var length: float = players["soldier"].get_animation("rig/" + clip).length
			var t := length * col / SAMPLES
			label.text = "rig/%s (from the %s)  t=%.2f s\nSoldier                Zombie" % [clip, CLIPS[row][1], t]
			for who in players:
				var ap: AnimationPlayer = players[who]
				ap.play("rig/" + clip)
				ap.seek(t, true)
				ap.pause()
			await get_tree().process_frame
			await RenderingServer.frame_post_draw
			var img := get_viewport().get_texture().get_image()
			img.convert(Image.FORMAT_RGB8)
			if img.get_size() != CELL:
				img.resize(CELL.x, CELL.y)
			sheet.blit_rect(img, Rect2i(Vector2i.ZERO, CELL), Vector2i(col * CELL.x, row * CELL.y))
	var path := out_dir.path_join("sheet.png")
	sheet.save_png(path)
	print("RIG: wrote %s" % path)
