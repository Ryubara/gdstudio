## Walks the menus for a capture: the main menu, each tab of settings, then (with `-- --game`) the
## game with the pause menu and its settings over it. Every step holds for `STEP` seconds.
##
## Two ways to run it:
## - with Movie Maker through the kit, for a desktop-sized window:
##   `gds godot -- --path game --write-movie out/menus.png --fixed-fps 10 --resolution 1920x1080
##   --quit-after 45 res://tools/capture/menus_tour.tscn`
## - for a phone-sized window (Movie Maker crops a canvas wider than 1920 units), with
##   `--shots=<dir>` after the engine's `--`: each step's real window pixels are saved as a PNG:
##   `gds godot -- --path game --resolution 844x390 res://tools/capture/menus_tour.tscn --
##   --shots=out`
## Add `--game` for the part over the game. It lives in tools/, which the export leaves out.
extends Node

const STEP := 0.9
const MAIN_MENU := "res://ui/menus/main_menu.tscn"
const SETTINGS := "res://ui/menus/settings_menu.tscn"
const GAME := "res://main.tscn"

var _shots := ""
var _count := 0


func _ready() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--shots="):
			_shots = argument.trim_prefix("--shots=")
	if "--game" in OS.get_cmdline_user_args():
		await _over_the_game()
	else:
		await _menus()
	get_tree().quit()


func _menus() -> void:
	UIRouter.reset(MAIN_MENU, UITransition.Kind.CUT)
	await _hold()
	UIRouter.push(SETTINGS, UITransition.Kind.SLIDE)
	await _hold()
	var settings := UIRouter.top() as SettingsMenu
	for tab in [1, 2]:
		settings.select_tab(tab, false)
		await _hold()


func _over_the_game() -> void:
	var game: Node = (load(GAME) as PackedScene).instantiate()
	add_child(game)
	await _hold()
	ScreenHost.current.open_pause()
	await _hold()
	UIRouter.push(SETTINGS, UITransition.Kind.SLIDE)
	await _hold()


## Waits `seconds` and, when asked for shots, saves what the window shows.
func _hold(seconds := STEP) -> void:
	await get_tree().create_timer(seconds, true).timeout
	if _shots.is_empty():
		return
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(_shots)
	var image := get_viewport().get_texture().get_image()
	image.save_png("%s/step%02d.png" % [_shots, _count])
	_count += 1
