## Measures what the minimap costs: the game's map with a minimap moving over it, once for each
## setting that matters (no minimap, the live camera every frame, shaded, rate limited, still, the
## image source) and with 100, 500 and 1000 markers as pooled icons next to the same number drawn by
## one `_draw` call. Each case runs 90 frames and then measures 240, with vsync off and the frame
## rate uncapped, and prints one line starting `BENCH` with a JSON object: milliseconds a frame
## (mean and 95th percentile), draw calls and the minimap viewport's own
## draw calls and render times.
##
## Run it windowed through the kit, in the renderer you want to measure:
## `gds godot -- --path game --rendering-method gl_compatibility
##   res://tools/bench/minimap_bench.tscn`
## It lives in tools/, which the export leaves out, and nothing in the game refers to it.
extends Node

## The cases, run in order. `live`: the live camera is on; `unshaded`, `rate` (Hz, 0 every frame),
## `still` (the view does not move), `image`, `markers` (how many), `draw` (the `_draw` version of
## the markers instead of pooled icons), `minimap` (any minimap at all).
const CASES: Array[Dictionary] = [
	{"name": "no_minimap", "minimap": false},
	{"name": "live_every_frame", "minimap": true, "live": true, "unshaded": true, "rate": 0.0},
	{"name": "live_lit_every_frame", "minimap": true, "live": true, "unshaded": false, "rate": 0.0},
	{"name": "live_30hz", "minimap": true, "live": true, "unshaded": true, "rate": 30.0},
	{"name": "live_15hz", "minimap": true, "live": true, "unshaded": true, "rate": 15.0},
	{
		"name": "live_half_resolution",
		"minimap": true,
		"live": true,
		"unshaded": true,
		"rate": 0.0,
		"scale": 0.5
	},
	{
		"name": "live_still",
		"minimap": true,
		"live": true,
		"unshaded": true,
		"rate": 0.0,
		"still": true
	},
	{"name": "image_source", "minimap": true, "live": false},
	{"name": "markers_100_icons", "minimap": true, "live": false, "markers": 100},
	{"name": "markers_500_icons", "minimap": true, "live": false, "markers": 500},
	{"name": "markers_1000_icons", "minimap": true, "live": false, "markers": 1000},
	{"name": "markers_100_drawn", "minimap": true, "live": false, "markers": 100, "draw": true},
	{"name": "markers_500_drawn", "minimap": true, "live": false, "markers": 500, "draw": true},
	{"name": "markers_1000_drawn", "minimap": true, "live": false, "markers": 1000, "draw": true},
	{
		"name": "full_every_frame_500_icons",
		"minimap": true,
		"live": true,
		"unshaded": true,
		"rate": 0.0,
		"markers": 500
	},
]

## Frames a case runs before it is measured, and frames measured (fewer in a browser, where a
## frame can take a tenth of a second without a GPU).
var _warm_up := 90
var _measured := 240
var _main: Node
var _minimap: Minimap
var _dummy := Node3D.new()
var _carriers: Array[Node3D] = []
var _mock: Control
var _case := -1
var _frame := 0
var _times: Array[float] = []
var _calls := 0.0
var _view_calls := 0.0
var _view_cpu := 0.0
var _view_gpu := 0.0
var _clock := 0.0
var _pass_usec := 0.0


func _ready() -> void:
	if OS.has_feature("web"):
		_warm_up = 20
		_measured = 60
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	_main = load("res://main.tscn").instantiate()
	add_child(_main)
	add_child(_dummy)
	_minimap = _main.get_node("MinimapLayer/Minimap")
	_minimap.target = _dummy
	(_main.get_node("MinimapLayer/MapScreen") as Control).hide()
	print(
		(
			"BENCH_INFO renderer=%s gpu=%s"
			% [
				ProjectSettings.get_setting("rendering/renderer/rendering_method"),
				RenderingServer.get_video_adapter_name(),
			]
		)
	)
	await get_tree().process_frame
	_next_case()


func _process(delta: float) -> void:
	if _case < 0 or _case >= CASES.size():
		return
	_clock += delta
	# The subject goes round in a circle at a run, so a live view that follows it always moves.
	if not CASES[_case].get("still", false):
		var angle := _clock * 0.4
		_dummy.global_position = Vector3(cos(angle) * 14.0, 0.5, sin(angle) * 14.0)
	for carrier in _carriers:
		carrier.global_position.x += sin(_clock + carrier.get_index()) * delta
	_frame += 1
	if _frame <= _warm_up:
		return
	_times.append(delta * 1000.0)
	_calls += RenderingServer.get_rendering_info(
		RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME
	)
	var rid := (_minimap.get_node("%LiveView") as SubViewport).get_viewport_rid()
	_view_calls += RenderingServer.viewport_get_render_info(
		rid,
		RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE,
		RenderingServer.VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME
	)
	_pass_usec += _minimap.marker_pass_usec()
	_view_cpu += RenderingServer.viewport_get_measured_render_time_cpu(rid)
	_view_gpu += RenderingServer.viewport_get_measured_render_time_gpu(rid)
	if _times.size() >= _measured:
		_report()
		_next_case()


func _next_case() -> void:
	_case += 1
	if _case >= CASES.size():
		print("BENCH_DONE")
		get_tree().quit()
		return
	var settings := CASES[_case]
	_clear_markers()
	_minimap.get_parent().visible = settings.get("minimap", false)
	_minimap.visible = settings.get("minimap", false)
	_minimap.source = (
		Minimap.Source.LIVE_CAMERA if settings.get("live", false) else Minimap.Source.IMAGE
	)
	if not settings.get("live", false):
		_minimap.image = (
			load("res://world/prototype/prototype_minimap.png")
			if ResourceLoader.exists("res://world/prototype/prototype_minimap.png")
			else load("res://assets/ui/minimap/square.png")
		)
		_minimap.image_world_rect = Rect2(-26.0, -26.0, 52.0, 52.0)
	_minimap.live_unshaded = settings.get("unshaded", true)
	_minimap.map_update_rate = settings.get("rate", 0.0)
	_minimap.live_resolution_scale = settings.get("scale", 1.0)
	_minimap.still_refresh_seconds = 1.0
	_minimap.pool_prewarm = 0
	var rid := (_minimap.get_node("%LiveView") as SubViewport).get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(rid, true)
	_make_markers(settings.get("markers", 0), settings.get("draw", false))
	_minimap.request_refresh()
	_frame = 0
	_times.clear()
	_calls = 0.0
	_view_calls = 0.0
	_pass_usec = 0.0
	_view_cpu = 0.0
	_view_gpu = 0.0


func _make_markers(count: int, drawn: bool) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 884
	if drawn:
		_mock = _MockLayer.new()
		(_mock as _MockLayer).points.resize(count)
		for i in count:
			(_mock as _MockLayer).points[i] = Vector2(
				rng.randf_range(0.0, 220.0), rng.randf_range(0.0, 220.0)
			)
		_minimap.get_node("%Icons").add_child(_mock)
		return
	for i in count:
		var carrier := Node3D.new()
		add_child(carrier)
		carrier.global_position = Vector3(
			rng.randf_range(-22.0, 22.0), 0.5, rng.randf_range(-22.0, 22.0)
		)
		var marker := MinimapMarker.new()
		marker.clamp_to_edge = true
		carrier.add_child(marker)
		_carriers.append(carrier)


func _clear_markers() -> void:
	for carrier in _carriers:
		carrier.free()
	_carriers.clear()
	if _mock != null:
		_mock.free()
		_mock = null


func _report() -> void:
	var sorted := _times.duplicate()
	sorted.sort()
	var mean := 0.0
	for time in _times:
		mean += time
	mean /= _times.size()
	var count := float(_times.size())
	var result := {
		"case": CASES[_case]["name"],
		"frame_ms": snappedf(mean, 0.001),
		"frame_p95_ms": snappedf(sorted[int(sorted.size() * 0.95)], 0.001),
		"draw_calls": snappedf(_calls / count, 0.1),
		"view_draw_calls": snappedf(_view_calls / count, 0.1),
		"marker_pass_ms": snappedf(_pass_usec / count / 1000.0, 0.001),
		"view_cpu_ms": snappedf(_view_cpu / count, 0.001),
		"view_gpu_ms": snappedf(_view_gpu / count, 0.001),
		"icons_made": _minimap.pool().made(),
		"snapshots": _minimap.snapshots_taken(),
	}
	print("BENCH ", JSON.stringify(result))


## What one `_draw` call costs for the same markers, for the comparison.
class _MockLayer:
	extends Control
	var points := PackedVector2Array()
	var texture: Texture2D = preload("res://assets/ui/minimap/dot.png")

	func _process(delta: float) -> void:
		for i in points.size():
			points[i].x += sin(Time.get_ticks_msec() * 0.001 + i) * delta
		queue_redraw()

	func _draw() -> void:
		for point in points:
			draw_texture_rect(
				texture, Rect2(point - Vector2(7.0, 7.0), Vector2(14.0, 14.0)), false, Color.WHITE
			)
