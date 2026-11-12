## The game server of `--server` (`gameplay/net/net_server.tscn`, the same scene under the same
## parent, so the world hash is the same), with the rules a gate changes on purpose: `--hold-ticks
## N` sets `NetServer.hold_ticks` (`--hold-ticks 0` is the server's half of the bargain taken out,
## the teeth check of `tools/net/bad_network_gate.py --break hold`). `--port 0` takes a free port;
## the `listening` line says which. `--ai N` puts a crowd of N AI characters in the map, each
## walking a circle (`AiCrowd`; `--ai-real` the guards as they are), for the AI's bytes and costs
## (`tools/net/bandwidth.py --ai`, gdstudio #970). `--hitscan` turns the pistol's
## `WeaponDef.hitscan` on for every body (`bandwidth.py --shoot --hitscan`, gdstudio #1252).
##
## `<godot> --headless --path game -s res://tools/net/gate_server.gd -- --port 0 [--hold-ticks 0]
## [--ai 120] [--ai-real] [--hitscan]`
extends SceneTree

const SERVER := "res://gameplay/net/net_server.tscn"
const PISTOL := "res://gameplay/weapon/pistol.tres"


func _initialize() -> void:
	var args := NetArgs.new()
	# The `.tres` every body's loadout holds, loaded once: set before the bodies are made.
	(load(PISTOL) as WeaponDef).hitscan = args.has("hitscan")
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
