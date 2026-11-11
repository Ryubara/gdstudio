class_name NetPlayProbe
extends Node
## For the browser half of the bad-network proof: a page opened with `?play&netplay&url=ws://...`
## plays the game online with a predicting client (`NetClient`) whose body walks the circles of a
## `CirclingController`, draws the other players (`RemotePlayers`) and writes what the client
## measured (`NetPlayReport`) to `window.gdnet` four times a second. A script that drives the page
## (`tools/web_smoke/net_play_smoke.py`) freezes the page's thread, sets `window.gdnet.stop` to
## stand the body still, and judges the numbers. It joins after the level's warm-up and its
## frames settle (`JoinWait`), as the online game does. It does nothing off the
## web or without `?netplay`, so a player's page pays for nothing; the player rig adds it at run
## time (`attach`), so no scene ships it. Online play itself is a later feature: this is a probe.

## Seconds between two writes.
const PERIOD := 0.25
## Seconds the body walks unless the page says stop first.
const WALK_SECONDS := 600.0

@export_group("Nodes")
## The local body the client predicts.
@export var player: Player

var client: NetClient
var remote: RemotePlayers
var ai: AiReplica
var _object: JavaScriptObject
var _walker: CirclingController
var _steps := 0
var _since := 0.0


## True on a web page opened with `?netplay`.
static func asked() -> bool:
	return (
		OS.has_feature("web")
		and bool(
			JavaScriptBridge.eval("new URLSearchParams(window.location.search).has('netplay')")
		)
	)


## Adds a probe beside `body`'s rig when the page asked for one (null otherwise).
static func attach(parent: Node, body: Player) -> NetPlayProbe:
	if not asked() or body == null:
		return null
	var probe := NetPlayProbe.new()
	probe.name = &"NetPlayProbe"
	probe.player = body
	parent.add_child(probe)
	return probe


func _ready() -> void:
	set_physics_process(false)
	if not asked() or player == null:
		return
	_object = JavaScriptBridge.create_object("Object")
	JavaScriptBridge.get_interface("window").gdnet = _object
	_object.state = "starting"
	_object.stop = false
	_object.report = "{}"
	_walker = CirclingController.new()
	_walker.name = &"CirclingController"
	_walker.seconds = WALK_SECONDS
	_walker.body = player
	player.add_child(_walker)
	player.controller = _walker
	# Beside the rig, in the scene that holds the map.
	var scene := get_parent().get_parent()
	remote = RemotePlayers.new()
	remote.name = &"RemotePlayers"
	scene.add_child.call_deferred(remote)
	# The server's AI characters, drawn and timed (gdstudio #970).
	ai = AiReplica.new()
	ai.name = &"AiReplica"
	ai.keep_times = true
	scene.add_child.call_deferred(ai)
	client = NetClient.new()
	client.name = &"NetClient"
	client.join_on_ready = false
	client.player = player
	client.remote_players = remote
	client.ai_replica = ai
	# The map node hashes the world, as the server's `world_root` (`main.tscn`'s `World`).
	var map := scene.get_node_or_null(^"World")
	client.world_root = map if map != null else scene
	client.player_name = "Browser"
	client.welcomed.connect(_on_welcomed)
	client.refused.connect(func(reason: int) -> void: _object.state = "refused %d" % reason)
	client.disconnected.connect(func() -> void: _object.state = "closed")
	scene.add_child.call_deferred(client)
	_join.call_deferred()


# Joins once the level is ready (`JoinWait`): its warm-up's first draws (the reflection probes,
# every material inside each) stall a software-drawn page for up to a second a frame, and a seat
# taken meanwhile met two to four of them in its first three seconds (kit #1106).
func _join() -> void:
	var wait := JoinWait.new()
	wait.stage_changed.connect(
		func(_stage: JoinWait.Stage) -> void: _object.state = wait.stage_name()
	)
	await wait.run(self)
	_object.settle_ms = wait.settle_ms
	var address := WebSocketLink.server_url()
	_object.url = address
	if client.join(address) != OK:
		_object.state = "refused"
		return
	_object.state = "connecting"
	set_physics_process(true)


func _physics_process(delta: float) -> void:
	if client.is_seated():
		_steps += 1
		if bool(_object.stop):
			_walker.stop()
	_since += delta
	if _since >= PERIOD:
		_since = 0.0
		_publish()


func _on_welcomed(_slot: int) -> void:
	_object.state = "seated"
	_steps = 0
	_walker.restart(player.global_position)


func _publish() -> void:
	var line := NetPlayReport.of(client, remote, _steps)
	line["standing"] = _walker.is_standing()
	line["fps"] = Engine.get_frames_per_second()
	_object.report = JSON.stringify(line)
