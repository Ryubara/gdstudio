extends SceneTree
## Plays a set of the Universal Animation Library's clips on every character model and prints,
## for each, the feet against the floor and the deepest limb overlap (kit #1149).
##
## Run it headless from the game's folder; the table goes to the output and, with a path after
## `--`, to that JSON file:
##
##     godot --headless --path . -s tools/mannequin/measure_bodies.gd -- <out.json>
##
## The two Quaternius mannequins are measured first: a new body is read against them.

const MEASURE := preload("res://tests/fixtures/body_measure.gd")
const LIBRARIES := {
	&"ual1": "res://assets/animation/universal/ual1.glb",
	&"ual2": "res://assets/animation/universal/ual2.glb",
}
const MODELS: Array[String] = [
	"res://assets/characters/mannequin/mannequin_male.glb",
	"res://assets/characters/mannequin/mannequin_female.glb",
	"res://assets/characters/prototype/form_male.glb",
	"res://assets/characters/prototype/form_female.glb",
	"res://assets/characters/prototype/form_chibi.glb",
	"res://assets/characters/prototype/joint_male.glb",
	"res://assets/characters/prototype/joint_female.glb",
	"res://assets/characters/prototype/joint_chibi.glb",
	"res://assets/characters/prototype/facet_male.glb",
	"res://assets/characters/prototype/facet_female.glb",
	"res://assets/characters/prototype/facet_chibi.glb",
]
const CLIPS: Array[StringName] = [
	&"ual1/Idle",
	&"ual1/Walk",
	&"ual1/Jog_Fwd",
	&"ual1/Sprint",
	&"ual1/Crouch_Idle",
	&"ual1/Crouch_Fwd",
	&"ual1/Jump",
	&"ual1/Roll",
	&"ual1/Pistol_Aim_Neutral",
	&"ual1/Pistol_Reload",
	&"ual1/Punch_Jab",
	&"ual1/Sitting_Idle",
	&"ual1/Sword_Attack",
	&"ual1/Dance",
	&"ual2/Slide",
	&"ual2/Walk_Carry",
	&"ual2/Idle_FoldArms",
	&"ual2/Zombie_Walk_Fwd",
]


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var report := {}
	for path in MODELS:
		var body: BodyMeasure = MEASURE.stage(root, path, LIBRARIES)
		var scale := body.skeleton.motion_scale
		var rows := {}
		var worst_deep := 0.0
		var worst_overlap := 0.0
		for clip in CLIPS:
			var row := body.measure_clip(clip)
			row["missing"] = body.missing_tracks(clip).size()
			rows[String(clip)] = row
			worst_deep = minf(worst_deep, row["deepest"])
			worst_overlap = maxf(worst_overlap, row["overlap"])
		report[path.get_file()] = {"motion_scale": scale, "radii": body.radii(), "clips": rows}
		print(
			(
				"%-24s scale %.3f  feet deepest %6.1f mm  overlap %5.1f mm"
				% [path.get_file(), scale, worst_deep * 1000.0, worst_overlap * 1000.0]
			)
		)
		for clip in CLIPS:
			var row: Dictionary = rows[String(clip)]
			print(
				(
					"    %-24s feet %6.1f .. %6.1f mm  overlap %5.1f mm %s  missing %d"
					% [
						clip,
						row["deepest"] * 1000.0,
						row["highest"] * 1000.0,
						row["overlap"] * 1000.0,
						row["pair"],
						row["missing"]
					]
				)
			)
		body.free_nodes()
	var arguments := OS.get_cmdline_user_args()
	if not arguments.is_empty():
		var file := FileAccess.open(arguments[0], FileAccess.WRITE)
		file.store_string(JSON.stringify(report, " "))
		file.close()
	quit()
