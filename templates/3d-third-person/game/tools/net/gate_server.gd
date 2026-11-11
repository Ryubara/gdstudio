## The game server of `--server` (`gameplay/net/net_server.tscn`, the same scene under the same
## parent, so the world hash is the same), with the rules a gate changes on purpose: `--hold-ticks
## N` sets `NetServer.hold_ticks` (`--hold-ticks 0` is the server's half of the bargain taken out,
## the teeth check of `tools/net/bad_network_gate.py --break hold`). `--port 0` takes a free port;
## the `listening` line says which. `--ai N` puts a crowd of N AI characters in the map, each
## walking a circle (`AiCrowd`; `--ai-real` the guards as they are), for the AI's bytes and costs
## (`tools/net/bandwidth.py --ai`, gdstudio #970).
##
## `<godot> --headless --path game -s res://tools/net/gate_server.gd -- --port 0 [--hold-ticks 0]
## [--ai 120] [--ai-real]`
extends SceneTree

const SERVER := "res://gameplay/net/net_server.tscn"


func _initialize() -> void:
	var args := NetArgs.new()
	var server := (load(SERVER) as PackedScene).instantiate() as NetServer
	if args.has("hold-ticks"):
		server.hold_ticks = args.get_int("hold-ticks", server.hold_ticks)
	root.add_child(server)
	current_scene = server
	var crowd_size := args.get_int("ai", 0)
	if crowd_size > 0:
		var crowd := AiCrowd.new()
		crowd.name = "AiCrowd"
		crowd.count = crowd_size
		crowd.real = args.has("ai-real")
		server.add_child(crowd)
		crowd.spawn(server.get_node("World"))
