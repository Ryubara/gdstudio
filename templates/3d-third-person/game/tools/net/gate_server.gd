## The game server of `--server` (`gameplay/net/net_server.tscn`, the same scene under the same
## parent, so the world hash is the same), with the rules a gate changes on purpose: `--hold-ticks
## N` sets `NetServer.hold_ticks` (`--hold-ticks 0` is the server's half of the bargain taken out,
## the teeth check of `tools/net/bad_network_gate.py --break hold`). `--port 0` takes a free port;
## the `listening` line says which.
##
## `<godot> --headless --path game -s res://tools/net/gate_server.gd -- --port 0 [--hold-ticks 0]`
extends SceneTree

const SERVER := "res://gameplay/net/net_server.tscn"


func _initialize() -> void:
	var args := NetArgs.new()
	var server := (load(SERVER) as PackedScene).instantiate() as NetServer
	if args.has("hold-ticks"):
		server.hold_ticks = args.get_int("hold-ticks", server.hold_ticks)
	root.add_child(server)
	current_scene = server
