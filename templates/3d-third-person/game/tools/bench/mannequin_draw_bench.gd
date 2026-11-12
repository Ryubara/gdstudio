extends Node3D
## What drawing a prototype mannequin (kit #1149) costs a browser frame, against the Quaternius
## male it would replace (kit #1186): crowds of 1, 8 and 16 bodies of one model playing `Walk`
## in place, under the game's sun (shadows on), at a distance inside each level of detail of the
## prototype bodies (`mannequin_import.gd`: 0 to 9 m, 9 to 22 m, past 22 m).
##
## Each cell is a model, a count and a level, measured over `frames` frames after `warm` frames,
## in `rounds` rounds that each walk every cell (a busy machine moves every cell alike); the
## `none` cells (no body) are the floor and the sun alone. Sixteen bodies near are split three
## more ways: `<model>/frozen` (drawn, no clip or skeleton moves: the drawing of a still skinned
## body), `<model>/hidden` (the clips and skeletons run, nothing is drawn: the animation's
## processor work) and `form/notwist` (`form` with its `MannequinTwist` off). A row is the median
## of the rounds' mean
## frames (wall clock between two process frames), the 95th percentile, and the draw calls and
## primitives a frame (`RenderingServer.get_rendering_info`), which say which level was drawn.
##
## Before the cells, each model is shown once, one body near, in turn (`order` rotates which
## goes first): the frames after a body first appears are its first-use hitch. The browser's
## probe (`mannequin_draw_bench.py`) records every `requestAnimationFrame` delta and every
## program WebGL links under the cell the bench names in `window.__cell`.
##
## On the web the page's query sets `rounds`, `frames`, `warm`, `order`, `first` (0: no first
## appearances) and `cells` (cell keys measured in place of the full list, any variant at any
## level: `?rounds=12&cells=facet/16/lod2,facet/notwist/16/lod2`). Make the build and run the
## probe with the kit:
## `gds template bench-web 3d-third-person mannequin_draw_bench --run`
## `--probe-args="--gpu --uncapped"` (no `--probe-args`: SwiftShader).
## It prints one line of JSON that starts with `MANNEQUIN_DRAW_BENCH` and, on the web, puts it in
## `window.__mannequin_draw_bench`. `MANNEQUIN_DRAW_SHOW=facet:16:0` (model, count, level) only
## stands that crowd, for a Movie Maker capture. It lives in tools/, which the export leaves out.

const MODELS := {
	"quaternius": "res://assets/characters/mannequin/mannequin_male.glb",
	"form": "res://assets/characters/prototype/form_male.glb",
	"joint": "res://assets/characters/prototype/joint_male.glb",
	"facet": "res://assets/characters/prototype/facet_male.glb",
}
const LIBRARY := "res://assets/animation/universal/ual1.glb"
const DAYLIGHT := "res://world/lighting/daylight.tscn"
const FLOOR := "res://assets/materials/prototype/prototype_floor.tres"
const CLIP := &"ual1/Walk"
const COUNTS: Array[int] = [1, 8, 16]
## The first row's distance from the camera (m) at each level of detail; the second row stands
## `ROW_GAP` behind it, and every body stays inside its level's band.
const LEVEL_DISTANCE: Array[float] = [4.5, 14.0, 30.0]
const ROW_GAP := 1.5
const COLUMNS := 8
const SPACING := 0.9
const CAMERA_HEIGHT := 1.5
## Frames each model is watched for after it first appears.
const FIRST_USE_FRAMES := 30

var rounds := 3
var frames := 150
var warm := 30
var order := 0
## Off (`first=0`): no first appearances before the cells.
var first := true
## Cell keys (`facet/16/lod2`, `facet/notwist/16/lod2`) that replace the full list when set.
var only: Array[String] = []

var _camera: Camera3D
## Model name to its pool of `COUNTS.max()` bodies, hidden and still until a cell shows them.
var _pools: Dictionary[String, Array] = {}
var _last_us := 0
var _samples := PackedInt32Array()
var _draw_calls := 0
var _primitives := 0
var _measuring := false


func _ready() -> void:
	_read_query()
	add_child((load(DAYLIGHT) as PackedScene).instantiate())
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(120.0, 120.0)
	plane.material = load(FLOOR)
	ground.mesh = plane
	add_child(ground)
	_camera = Camera3D.new()
	_camera.position = Vector3(0.0, CAMERA_HEIGHT, 0.0)
	_camera.rotation = Vector3(deg_to_rad(-4.0), 0.0, 0.0)
	add_child(_camera)
	_camera.make_current()
	var library: AnimationLibrary = load(LIBRARY)
	for model: String in MODELS:
		var scene: PackedScene = load(MODELS[model])
		var pool: Array[Node3D] = []
		for index in COUNTS.max():
			var body: Node3D = scene.instantiate()
			var player := AnimationPlayer.new()
			body.add_child(player)
			player.add_animation_library(&"ual1", library)
			add_child(body)
			player.play(CLIP)
			player.seek(index * 0.071)
			pool.append(body)
		_pools[model] = pool
	_show("", 0, 0)
	var shown_crowd := OS.get_environment("MANNEQUIN_DRAW_SHOW")
	if shown_crowd.is_empty():
		_run.call_deferred()
	else:
		var parts := shown_crowd.split(":")
		_show(parts[0], int(parts[1]), int(parts[2]))


func _process(_delta: float) -> void:
	var now := Time.get_ticks_usec()
	if _measuring:
		if _last_us > 0:
			_samples.append(now - _last_us)
		_draw_calls += RenderingServer.get_rendering_info(
			RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME
		)
		_primitives += RenderingServer.get_rendering_info(
			RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME
		)
	_last_us = now


func _run() -> void:
	var first_use: Array[Dictionary] = []
	var names: Array = MODELS.keys()
	for step in names.size() if first else 0:
		var model: String = names[(step + order) % names.size()]
		first_use.append(await _first_use(model))
	_show("", 0, 0)
	var cells := _cells()
	var rows: Dictionary[String, Array] = {}
	for round_index in rounds:
		for cell: Array in cells:
			var key := "%s/%d/lod%d" % cell
			_show(cell[0], cell[1], cell[2])
			for _i in warm:
				await get_tree().process_frame
			_begin(key)
			for _i in frames:
				await get_tree().process_frame
			if not rows.has(key):
				rows[key] = []
			rows[key].append(_end())
	var results: Array[Dictionary] = []
	for cell: Array in cells:
		var key := "%s/%d/lod%d" % cell
		results.append(_row(key, cell, rows[key]))
	var line := (
		JSON
		. stringify(
			{
				"rounds": rounds,
				"frames": frames,
				"order": order,
				"first_use": first_use,
				"results": results,
			}
		)
	)
	print("MANNEQUIN_DRAW_BENCH ", line)
	if OS.has_feature("web"):
		JavaScriptBridge.eval("window.__mannequin_draw_bench = %s;" % line, true)
	else:
		get_tree().quit()


# Every cell in the order a round walks them: each level, each count, no body then each model;
# the split of sixteen near bodies last.
func _cells() -> Array[Array]:
	var cells: Array[Array] = []
	if not only.is_empty():
		for key in only:
			var parts := key.split("/")
			var model := "/".join(parts.slice(0, parts.size() - 2))
			cells.append([model, int(parts[-2]), int(parts[-1].trim_prefix("lod"))])
		return cells
	for level in LEVEL_DISTANCE.size():
		cells.append(["none", 0, level])
		for count in COUNTS:
			for model: String in MODELS:
				cells.append([model, count, level])
	for model: String in MODELS:
		cells.append([model + "/frozen", COUNTS.max(), 0])
		cells.append([model + "/hidden", COUNTS.max(), 0])
	cells.append(["form/notwist", COUNTS.max(), 0])
	return cells


# One body of `model` shown near for the first time: the frames after it appears.
func _first_use(model: String) -> Dictionary:
	_show("", 0, 0)
	for _i in warm:
		await get_tree().process_frame
	_show(model, 1, 0)
	_begin("first/" + model)
	for _i in FIRST_USE_FRAMES:
		await get_tree().process_frame
	var sorted := _samples.duplicate()
	var summary := _end()
	sorted.sort()
	summary["model"] = model
	summary["worst_ms"] = snappedf(sorted[-1] / 1000.0, 0.001) if not sorted.is_empty() else 0.0
	return summary


func _begin(key: String) -> void:
	_samples.clear()
	_draw_calls = 0
	_primitives = 0
	_last_us = 0
	_measuring = true
	if OS.has_feature("web"):
		JavaScriptBridge.eval("window.__cell = %s;" % JSON.stringify(key), true)


func _end() -> Dictionary:
	_measuring = false
	if OS.has_feature("web"):
		JavaScriptBridge.eval("window.__cell = '';", true)
	var count := maxi(_samples.size(), 1)
	var summary := _summary(_samples)
	summary["draw_calls"] = snappedf(float(_draw_calls) / count, 0.1)
	summary["primitives"] = int(float(_primitives) / count)
	return summary


# Shows `count` bodies of `model` at level `level`'s distance, two rows of up to `COLUMNS`, and
# hides and stops every other body. `<model>/frozen` stops them, `<model>/hidden` hides them and
# `form/notwist` turns the twist off.
func _show(model: String, count: int, level: int) -> void:
	var source := model.get_slice("/", 0)
	var variant := model.get_slice("/", 1)
	for pool_name: String in _pools:
		var pool: Array = _pools[pool_name]
		for index in pool.size():
			var body: Node3D = pool[index]
			var shown := pool_name == source and index < count
			body.visible = shown and variant != "hidden"
			var moving := shown and variant != "frozen"
			body.process_mode = PROCESS_MODE_INHERIT if moving else PROCESS_MODE_DISABLED
			var modifier := body.find_child("MannequinTwist", true, false) as SkeletonModifier3D
			if modifier != null:
				modifier.active = variant != "notwist"
			if not shown:
				continue
			var in_row := mini(count, COLUMNS)
			var column := index % COLUMNS
			var row := index / COLUMNS
			body.position = Vector3(
				(column - (in_row - 1) * 0.5) * SPACING,
				0.0,
				-(LEVEL_DISTANCE[level] + row * ROW_GAP)
			)


static func _row(key: String, cell: Array, runs: Array) -> Dictionary:
	var means: Array[float] = []
	var medians: Array[float] = []
	var p95s: Array[float] = []
	for run: Dictionary in runs:
		means.append(run.mean)
		medians.append(run.median)
		p95s.append(run.p95)
	means.sort()
	medians.sort()
	p95s.sort()
	var last: Dictionary = runs[-1]
	return {
		"cell": key,
		"model": cell[0],
		"count": cell[1],
		"level": cell[2],
		"frame_ms": means[means.size() / 2],
		"frame_ms_runs": means,
		"median_ms": medians[medians.size() / 2],
		"p95_ms": p95s[p95s.size() / 2],
		"draw_calls": last.draw_calls,
		"primitives": last.primitives,
	}


static func _summary(samples: PackedInt32Array) -> Dictionary:
	var sorted := samples.duplicate()
	sorted.sort()
	var total := 0
	for value in sorted:
		total += value
	var count := maxi(sorted.size(), 1)
	if sorted.is_empty():
		sorted.append(0)
	return {
		"mean": snappedf(float(total) / count / 1000.0, 0.001),
		"median": snappedf(sorted[sorted.size() / 2] / 1000.0, 0.001),
		"p95": snappedf(sorted[mini(int(count * 0.95), sorted.size() - 1)] / 1000.0, 0.001),
	}


func _read_query() -> void:
	if not OS.has_feature("web"):
		return
	var query := str(JavaScriptBridge.eval("window.location.search", true)).trim_prefix("?")
	for pair in query.split("&", false):
		var key := pair.get_slice("=", 0)
		var text := pair.get_slice("=", 1)
		if key == "cells":
			for cell in text.uri_decode().split(",", false):
				only.append(cell)
			continue
		var value := text.to_int() if text.is_valid_int() else 0
		match key:
			"rounds":
				rounds = maxi(value, 1)
			"frames":
				frames = maxi(value, 10)
			"warm":
				warm = maxi(value, 0)
			"order":
				order = maxi(value, 0)
			"first":
				first = value != 0
