class_name WebSocketLink
extends NetLink
## A client's link to a game server over a WebSocket, the same class on desktop and in the web
## build (a web export can only be a WebSocket client: it cannot listen).
## `connect_to_url("ws://host:8910")` starts it; `connected` fires once the handshake is done;
## `poll` once per physics tick reads every packet that came. Binary frames only.
##
## What it was built to survive (Deadnight #483, #502): a client whose loop froze for seconds
## reads nothing meanwhile, and the server's packets wait in this socket's buffer; the engine's
## default of 64 KB dropped the newest within a few seconds, so the buffer is 1 MB and 8192
## packets. `left_on_purpose()` tells a clean goodbye (1000, 1001) from a network that went.
##
## The closing handshake: Godot's `WebSocketPeer` throws away every packet that reaches it in the
## same `poll` as the other end's close frame (measured on 4.7.2, both directions), so a last packet
## sent right before a close is lost unless the receiver polled in between. `close()` therefore
## lingers: from the call nothing more is sent, and the close frame itself leaves `close_linger`
## seconds later, on a `poll`, so the server reads the last packets first. Keep polling until
## `closed`; a link freed before that looks to the server like a network that went.
##
## Where to connect comes from the command line (`-- --connect ws://host:8910`) or, on the web, from
## the page's address (`index.html?url=wss://host`): `server_url()`. A page served over `https` may
## only open `wss://` (the browser refuses `ws://` there), and `connect_to_url` refuses it first
## with a reason (`refusal`), never trying the downgrade.

## The default game port (the editor's MCP bridge here is 9080: check a port before choosing one).
const DEFAULT_PORT := 8910
## The engine's packet count limit, for both directions.
const MAX_QUEUED := 8192
## The close code `drop` ends the socket with (the private range): not a goodbye.
const DROP_CODE := 4000
## Seconds between `close()` and the close frame, for the server to read the last packets first.
const CLOSE_LINGER := 0.25

## Bytes the socket may hold unread: the server's packets of a frozen client wait here, and what
## does not fit is dropped, newest first (`NetLimits.BUFFER_SIZE`; a test sets it before
## `connect_to_url`).
var inbound_buffer := NetLimits.BUFFER_SIZE
## Seconds between `close()` and the close frame (`CLOSE_LINGER`; 0 closes at once).
var close_linger := CLOSE_LINGER
## Seconds from game start, for the linger (empty: the real clock).
var clock := Callable()
## Why the last `connect_to_url` was refused (empty when it was not).
var refusal := ""

var _ws: WebSocketPeer
var _url := ""
var _was_open := false
var _closed_emitted := false
var _close_code := NetLink.CLOSE_NONE
## When the lingering close frame leaves (-1: no close asked), and with which code.
var _close_at := -1.0
var _close_sent := false


## Starts connecting to `address` (`ws://` or `wss://`); the result is the error of the start, not
## of the connection. On a web page served over `https` a `ws://` address is refused
## (`ERR_UNAUTHORIZED`, and `refusal` says why).
func connect_to_url(address: String) -> Error:
	refusal = WebSocketLink.url_problem(address, WebSocketLink.page_protocol())
	if not refusal.is_empty():
		push_warning("WebSocketLink: %s" % refusal)
		return ERR_UNAUTHORIZED
	_url = address
	_was_open = false
	_closed_emitted = false
	_close_code = NetLink.CLOSE_NONE
	_close_at = -1.0
	_close_sent = false
	_ws = WebSocketPeer.new()
	_ws.inbound_buffer_size = inbound_buffer
	_ws.max_queued_packets = MAX_QUEUED
	return _ws.connect_to_url(address)


## The address it was asked to connect to.
func url() -> String:
	return _url


func send(data: PackedByteArray) -> bool:
	if not is_open():
		return false
	if _ws.send(data, WebSocketPeer.WRITE_MODE_BINARY) != OK:
		return false
	bytes_out += data.size()
	packets_out += 1
	return true


func poll() -> void:
	if _ws == null or _closed_emitted:
		return
	_ws.poll()
	var state := _ws.get_ready_state()
	if state == WebSocketPeer.STATE_OPEN and not _was_open:
		_was_open = true
		connected.emit()
	# Read to the floor, after a close too: what came before it is still delivered.
	while state != WebSocketPeer.STATE_CONNECTING and _ws.get_available_packet_count() > 0:
		var data := _ws.get_packet()
		bytes_in += data.size()
		packets_in += 1
		packet_received.emit(data)
	if _close_at >= 0.0 and not _close_sent and _now() >= _close_at:
		_close_sent = true
		_ws.close(NetLink.CLOSE_NORMAL)
	if state == WebSocketPeer.STATE_CLOSED:
		_close_code = _ws.get_close_code()
		_closed_emitted = true
		closed.emit()


func is_open() -> bool:
	return _ws != null and _close_at < 0.0 and _ws.get_ready_state() == WebSocketPeer.STATE_OPEN


## Says goodbye (1000): nothing more is sent, and the close frame leaves `close_linger` seconds
## later from `poll` (at once while still connecting, or with no linger).
func close() -> void:
	if _ws == null or _close_at >= 0.0:
		return
	_close_at = _now() + close_linger
	if close_linger <= 0.0 or _ws.get_ready_state() != WebSocketPeer.STATE_OPEN:
		_close_sent = true
		_ws.close(NetLink.CLOSE_NORMAL)


## Closes the socket with a code that is not a goodbye, as a network that went would look to the
## server (for tests of what a dropped player leaves).
func drop() -> void:
	if _ws != null and not _close_sent:
		_close_at = _now()
		_close_sent = true
		_ws.close(DROP_CODE, "dropped")


func close_code() -> int:
	return _close_code


func _now() -> float:
	if clock.is_valid():
		return float(clock.call())
	return Time.get_ticks_usec() / 1000000.0


## The server's address for this run: `--connect <url>` (or `--url`) after `--` on the command line,
## or on the web `?url=<url>` (or `?connect=`) in the page's address; `fallback` when neither says.
static func server_url(fallback := "") -> String:
	var search := ""
	if OS.has_feature("web"):
		search = str(JavaScriptBridge.eval("window.location.search"))
	return WebSocketLink.url_from(OS.get_cmdline_user_args(), search, fallback)


## `server_url` on given arguments and page search (`?url=...&probe`), for tests.
static func url_from(args: PackedStringArray, search: String, fallback := "") -> String:
	for i in args.size():
		var arg := args[i]
		for key: String in ["--connect", "--url"]:
			if arg.begins_with(key + "="):
				return arg.trim_prefix(key + "=")
			if arg == key and i + 1 < args.size():
				return args[i + 1]
	for pair in search.trim_prefix("?").split("&", false):
		var kv := pair.split("=", true, 1)
		if kv.size() == 2 and (kv[0] == "url" or kv[0] == "connect") and not kv[1].is_empty():
			return kv[1].uri_decode()
	return fallback


## The page's protocol on the web (`https:` or `http:`), empty off the web.
static func page_protocol() -> String:
	if not OS.has_feature("web"):
		return ""
	return str(JavaScriptBridge.eval("window.location.protocol"))


## Why `url` cannot be opened from a page of `protocol` (empty when it can): only `ws://` and
## `wss://`, and only `wss://` from an `https:` page (the browser blocks the downgrade as mixed
## content; refusing it here says so instead of a socket that never opens).
static func url_problem(address: String, protocol: String) -> String:
	if not (address.begins_with("ws://") or address.begins_with("wss://")):
		return "not a WebSocket address: '%s'" % address
	if protocol == "https:" and address.begins_with("ws://"):
		return "an https page may only open wss://, not '%s'" % address
	return ""
