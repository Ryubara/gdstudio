class_name MenuScene
extends Node
## The scene the project starts: shows the main menu on the router. Started with `--play` after the
## engine's `--` (or with `?play` in a browser's address) it goes straight to the game instead, for
## a tool that wants the game and not the menu. Started with `--server` (`NetArgs`) it is a
## headless game server: it goes to `server_scene` and shows nothing. Started with an address
## (`--connect ws://host:8910`, or `?url=` in a browser's address) it goes to `online_scene`, the
## online game (a page with `?netplay` is the bad-network probe's, which plays `game_scene`). The
## command line decides once a run: back from the game, the menu shows.

# The start options were acted on once this run (a later menu shows the menu).
static var _routed := false

## The first screen.
@export var main_menu: PackedScene
## The scene `--play` goes to.
@export_file("*.tscn") var game_scene := "res://main.tscn"
## The scene an address goes to: the game with a `NetClient`.
@export_file("*.tscn") var online_scene := "res://online_main.tscn"
## The scene `--server` goes to: the map and a `NetServer`.
@export_file("*.tscn") var server_scene := "res://gameplay/net/net_server.tscn"
## Goes straight to the game without showing the menu: for working on the game itself. The
## command-line flag and the address flag do the same without touching the scene.
@export var skip_menu := false

## Switches scene instead of the tree's own change when valid (a `Callable` taking the scene's
## path): a test must not replace the scene the runner stands in.
var scene_changer := Callable()
## The options it was started with (empty: the command line's; a test gives its own).
var net_args: NetArgs


func _ready() -> void:
	var args := net_args if net_args != null else NetArgs.new()
	if args.is_server():
		_go_to(server_scene)
		return
	# The touch controls turn touch-to-mouse off while they show; a menu needs a finger to press.
	Input.emulate_mouse_from_touch = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var first := not _routed or net_args != null
	_routed = true
	if first and wants_online(args):
		_go_to(online_scene)
		return
	if skip_menu or (first and wants_game()):
		_go_to(game_scene)
		return
	UIRouter.reset(main_menu, UITransition.Kind.FADE)


## Whether the game was started with a server's address (`--connect`, `--url`, `?url=`), and not as
## the bad-network probe's page (`?netplay`, which plays `game_scene` with its own client).
func wants_online(args: NetArgs) -> bool:
	if args.has("netplay"):
		return false
	return args.get_string("connect", args.get_string("url")).contains("://")


## Whether the game was asked for without the menu.
func wants_game() -> bool:
	if skip_menu:
		return true
	if "--play" in OS.get_cmdline_user_args():
		return true
	if OS.has_feature("web"):
		return bool(
			JavaScriptBridge.eval("new URLSearchParams(window.location.search).has('play')")
		)
	return false


func _go_to(scene: String) -> void:
	if scene_changer.is_valid():
		scene_changer.call(scene)
	else:
		get_tree().change_scene_to_file.call_deferred(scene)
