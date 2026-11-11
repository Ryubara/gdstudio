class_name NetArgs
extends RefCounted
## The options a game is started with after the engine's `--`: `--server` (run a headless game
## server, `NetServer`), `--port 8910` or `--port=8910`, `--connect ws://host:8910`,
## `--name Ada`, `--bot`. A word after a `--key` that does not itself start with `--` is its
## value; a key with none is `"true"`. On the web there is no command line: the page's address
## gives the same keys (`index.html?connect=wss://host&name=Ada`).
##
## `godot --headless --path game -- --server --port 8910` starts the server: the main scene
## (`MenuScene`) reads `is_server()` before it shows a menu.

var _values: Dictionary[String, String] = {}


## Reads `args` (the command line after `--` when omitted) and, in a web build, the page's query.
func _init(args: PackedStringArray = OS.get_cmdline_user_args()) -> void:
	if OS.has_feature("web") and args == OS.get_cmdline_user_args():
		var search: Variant = JavaScriptBridge.eval("window.location.search")
		for pair in str(search).trim_prefix("?").split("&", false):
			var key_value := pair.split("=", true, 1)
			_values[key_value[0]] = key_value[1].uri_decode() if key_value.size() > 1 else "true"
	var at := 0
	while at < args.size():
		var arg := args[at]
		at += 1
		if not arg.begins_with("--"):
			continue
		var parts := arg.trim_prefix("--").split("=", true, 1)
		if parts.size() > 1:
			_values[parts[0]] = parts[1]
		elif at < args.size() and not args[at].begins_with("--"):
			_values[parts[0]] = args[at]
			at += 1
		else:
			_values[parts[0]] = "true"


func has(key: String) -> bool:
	return _values.has(key)


func get_string(key: String, fallback := "") -> String:
	return _values.get(key, fallback)


## The option as a whole number, or `fallback` when it is missing or not a number.
func get_int(key: String, fallback := 0) -> int:
	var text: String = _values.get(key, "")
	return int(text) if text.is_valid_int() else fallback


## Started as a game server (`--server`; never in a web build, which cannot listen).
func is_server() -> bool:
	return has("server") and not OS.has_feature("web")


## The port a server listens on: `--port`, else the environment's `PORT` (Railway sets it), else
## `fallback`.
func port(fallback: int) -> int:
	var from_env := OS.get_environment("PORT")
	return get_int("port", int(from_env) if from_env.is_valid_int() else fallback)
