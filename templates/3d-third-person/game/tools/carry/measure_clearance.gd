## Measures how deep the held pistol sinks into the body in every clip the character carries it
## in, on both mannequins: for each clip it samples the pose at 12 times, puts the grip pose on
## the gripping hand (`CharacterAnimation`'s grip clip and bones) and prints the deepest point of
## the pistol that is inside the body, in millimetres (a negative number is clearance up to 10 cm,
## `-` more than that). See `PistolClearance` for how a point counts as inside.
##
## Run it headless from a game made from the template (`CARRY_BONES=hand_r,hand_l` changes the
## bones that take the grip, `CARRY_GRIP=ual1/Idle` the grip clip):
## `<godot> --headless --path game -s res://tools/carry/measure_clearance.gd`
## It lives in tools/, which the export leaves out.
extends SceneTree

const MODELS := [
	CharacterBodies.FEMALE,
	CharacterBodies.MALE,
]
const CLIPS: Array[StringName] = [
	CharacterClips.IDLE,
	CharacterClips.WALK,
	CharacterClips.RUN,
	CharacterClips.SPRINT,
	CharacterClips.CROUCH_IDLE,
	CharacterClips.CROUCH_WALK,
	CharacterClips.JUMP_START,
	CharacterClips.AIR,
	CharacterClips.LAND,
	CharacterClips.PUSH,
]
const SAMPLES := 12


func _initialize() -> void:
	var pistol := load("res://gameplay/weapon/pistol.tres") as WeaponDef
	var bones: Array[StringName] = pistol.grip_bones
	var grip_clip := pistol.grip_clip
	if OS.get_environment("CARRY_BONES") != "":
		bones = []
		for bone in OS.get_environment("CARRY_BONES").split(","):
			bones.append(StringName(bone))
	if OS.get_environment("CARRY_GRIP") != "":
		grip_clip = StringName(OS.get_environment("CARRY_GRIP"))
	print("grip bones ", bones, " clip ", grip_clip)
	for path: String in MODELS:
		var holder := Node3D.new()
		get_root().add_child(holder)
		var clearance := PistolClearance.new(holder, path)
		var grip := clearance.clip(grip_clip)
		var line := path.get_file().get_basename().trim_prefix("mannequin_") + ":"
		print(line)
		for clip_name in CLIPS:
			var anim := clearance.clip(clip_name)
			var worst := -1.0
			var at := 0.0
			for step in SAMPLES:
				var time := anim.length * step / SAMPLES
				clearance.pose(anim, time, grip, bones, 0.0)
				var depth := clearance.depth()
				if depth > worst:
					worst = depth
					at = time
			print("  %-18s deepest %6.1f mm at %.2f s" % [clip_name, worst * 1000.0, at])
		clearance.free_rig()
		holder.free()
	quit()
