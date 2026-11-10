class_name NetProbe
extends Node
## For browser tests of the network link: when the page is opened with `?netprobe&url=ws://...`,
## this connects a `WebSocketLink` to that server (`tools/net/echo_server.gd`), pings it twice a
## second and writes what it sees to `window.gdnet`, so a script that drives the page
## (`tools/web_smoke/net_link_smoke.py`) can read it: the state, a refusal, the round trips, and
## how many streamed packets came and whether in order. It does nothing off the web or without
## `?netprobe`, so a player's page pays for nothing.

## Seconds between two pings.
const PING_EVERY := 0.5
## Size of a ping: a tag byte and the send time in microseconds.
const PING_SIZE := 9
const PING_TAG := 0xEE
## The one byte that asks the echo server for its stream.
const STREAM_ASK := 0x01

var _link: WebSocketLink
var _object: JavaScriptObject
var _since_ping := 0.0
var _rtts: Array[float] = []
var _streamed := 0
var _in_order := true
var _gaps_over_100ms := 0
var _last_arrival_usec := 0
var _stream_asked := false


func _ready() -> void:
	set_physics_process(false)
	if not OS.has_feature("web"):
		return
	if not JavaScriptBridge.eval("new URLSearchParams(window.location.search).has('netprobe')"):
		return
	_object = JavaScriptBridge.create_object("Object")
	JavaScriptBridge.get_interface("window").gdnet = _object
	_object.state = "starting"
	_object.refusal = ""
	_object.want_stream = false
	_link = WebSocketLink.new()
	_link.packet_received.connect(_on_packet)
	_link.connected.connect(func() -> void: _object.state = "open")
	_link.closed.connect(_on_closed)
	var address := WebSocketLink.server_url()
	_object.url = address
	if _link.connect_to_url(address) != OK:
		_object.state = "refused"
		_object.refusal = _link.refusal
		return
	_object.state = "connecting"
	set_physics_process(true)


func _physics_process(delta: float) -> void:
	_link.poll()
	if not _link.is_open():
		return
	if not _stream_asked and bool(_object.want_stream):
		_stream_asked = true
		_link.send(PackedByteArray([STREAM_ASK]))
	_since_ping += delta
	if _since_ping >= PING_EVERY:
		_since_ping = 0.0
		var ping := PackedByteArray()
		ping.resize(PING_SIZE)
		ping[0] = PING_TAG
		ping.encode_u64(1, Time.get_ticks_usec())
		_link.send(ping)
	_publish()


func _on_packet(data: PackedByteArray) -> void:
	var now := Time.get_ticks_usec()
	if data.size() == PING_SIZE and data[0] == PING_TAG:
		_rtts.append((now - data.decode_u64(1)) / 1000.0)
		return
	if data.size() >= 4:
		if data.decode_u32(0) != _streamed:
			_in_order = false
		if _last_arrival_usec > 0 and now - _last_arrival_usec > 100000:
			_gaps_over_100ms += 1
		_last_arrival_usec = now
		_streamed += 1


func _on_closed() -> void:
	_object.state = "closed"
	_object.close_code = _link.close_code()
	_object.on_purpose = _link.left_on_purpose()
	_publish()


func _publish() -> void:
	_object.streamed = _streamed
	_object.in_order = _in_order
	_object.gaps_over_100ms = _gaps_over_100ms
	_object.pings = _rtts.size()
	_object.rtt_ms = JSON.stringify(_rtts)
	_object.bytes_in = _link.bytes_in
