class_name OnlineProbe
extends Node
## For the probe of online play (`tools/web_smoke/online.py`): the online game (`OnlineMain`)
## opened with `?onlineprobe` writes what its client measured to `window.gdonline` four times a
## second: `state` (`connecting`, `seated`, `refused version`, `closed`...) and `report`, a JSON
## line of `NetPlayReport` (round trip, corrections, the gap between the body and the server's
## point) with `players` (the puppets and this one), the overlay's `message`, the frame time's
## median and 95th percentile over the last `WINDOW_FRAMES` frames, and the CPU time of a frame's
## processing and physics. On the desktop `-- --onlineprobe` prints the same line once a second,
## starting `ONLINE_PROBE`, so the browser and a native client are measured alike. It does nothing
## without the flag, so a player pays for nothing; `OnlineMain` adds it at run time, so no scene
## ships it.

## Seconds between two writes on the web, and between two printed lines on the desktop.
const PERIOD := 0.25
const PRINT_PERIOD := 1.0
## Frames the frame-time percentiles are taken over.
const WINDOW_FRAMES := 240

var client: NetClient
var remote: RemotePlayers
## The overlay whose message is written as `message` (empty: none).
var status: OnlineStatus
## What the client is doing: `connecting`, `seated`, `refused <reason>`, `closed`.
var state := "connecting"
var _object: JavaScriptObject
var _steps := 0
var _since := 0.0
var _frame_us := PackedInt32Array()
var _puppet_us := PackedInt32Array()
var _last_frame := 0


## True on a web page opened with `?onlineprobe`, or a desktop game started with `--onlineprobe`.
static func asked() -> bool:
	if OS.has_feature("web"):
		return bool(
			JavaScriptBridge.eval("new URLSearchParams(window.location.search).has('onlineprobe')")
		)
	return "--onlineprobe" in OS.get_cmdline_user_args()


## Adds a probe under `parent` when it was asked for (null otherwise).
static func attach(
	parent: Node,
	with_client: NetClient,
	with_remote: RemotePlayers,
	with_status: OnlineStatus = null
) -> OnlineProbe:
	if not asked() or with_client == null:
		return null
	var probe := OnlineProbe.new()
	probe.name = &"OnlineProbe"
	probe.client = with_client
	probe.remote = with_remote
	probe.status = with_status
	parent.add_child(probe)
	return probe


func _ready() -> void:
	if OS.has_feature("web"):
		_object = JavaScriptBridge.create_object("Object")
		JavaScriptBridge.get_interface("window").gdonline = _object
		_object.report = "{}"
	_set_state("connecting")
	client.keep_frame_times = true
	client.welcomed.connect(func(_slot: int) -> void: _set_state("seated"))
	client.refused.connect(_on_refused)
	client.disconnected.connect(_on_disconnected)


func _process(delta: float) -> void:
	var now := Time.get_ticks_usec()
	if _last_frame > 0:
		_frame_us = _pushed(_frame_us, now - _last_frame)
	_last_frame = now
	_since += delta
	if _since >= (PERIOD if _object != null else PRINT_PERIOD):
		_since = 0.0
		_publish()


func _physics_process(_delta: float) -> void:
	if client.is_seated():
		_steps += 1
		if remote != null:
			_puppet_us = _pushed(_puppet_us, remote.last_frame_us)


## The report as it is written now.
func report() -> Dictionary:
	var line := NetPlayReport.of(client, remote, _steps, _puppet_us)
	var puppets := remote.slots().size() if remote != null else 0
	line["state"] = state
	line["players"] = puppets + (1 if client.is_seated() else 0)
	line["message"] = status.message() if status != null else ""
	line["fps"] = Engine.get_frames_per_second()
	line["frame_us_p50"] = NetPlayReport.percentile(_frame_us, 0.5)
	line["frame_us_p95"] = NetPlayReport.percentile(_frame_us, 0.95)
	line["process_ms"] = snappedf(Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0, 0.01)
	line["physics_ms"] = snappedf(
		Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0, 0.01
	)
	return line


func _publish() -> void:
	var line := JSON.stringify(report())
	if _object != null:
		_object.report = line
	else:
		print("ONLINE_PROBE " + line)
	# The client keeps every step's time: the window is enough for a report.
	if client.frame_times.size() > WINDOW_FRAMES * 4:
		client.frame_times = client.frame_times.slice(-WINDOW_FRAMES)


func _set_state(value: String) -> void:
	state = value
	if _object != null:
		_object.state = value


func _on_refused(reason: int) -> void:
	_set_state("refused %s" % str(NetWire.Refusal.find_key(reason)).to_lower())


func _on_disconnected() -> void:
	if not state.begins_with("refused"):
		_set_state("closed")


# `values` with `value` added and the oldest dropped past `WINDOW_FRAMES`.
static func _pushed(values: PackedInt32Array, value: int) -> PackedInt32Array:
	values.append(value)
	if values.size() > WINDOW_FRAMES:
		values.remove_at(0)
	return values
