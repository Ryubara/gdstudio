## The online overlay in the real online game, for a capture of each of its looks: Connecting (a
## server that never answers), a message with Back to menu (it did not answer), and another
## version with its hint. Each step holds for `STEP` seconds.
##
## Desktop, with Movie Maker: `gds godot -- --path game --write-movie out/status.png --fixed-fps 10
## --resolution 1920x1080 --quit-after 40 res://tools/capture/online_status_tour.tscn`. A phone's
## window (Movie Maker crops a canvas wider than 1920 units): `gds godot -- --path game
## --resolution 844x390 res://tools/capture/online_status_tour.tscn -- --shots=out`, which saves
## the window's own pixels at each step. It lives in tools/, which the export leaves out.
extends Node

const STEP := 1.2
const ONLINE := "res://online_main.tscn"
## A port nothing listens on, held open by nobody: the link waits, then fails.
const NOBODY := "ws://127.0.0.1:9"

var _shots := ""
var _count := 0


func _ready() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--shots="):
			_shots = argument.trim_prefix("--shots=")
	NetClient.next_url = NOBODY
	var online := (load(ONLINE) as PackedScene).instantiate() as OnlineMain
	var status := online.status
	# The overlay shows what the tour asks, whatever the closed port answers.
	status.client = null
	add_child(online)
	status.set_process(false)
	status._show(OnlineStatus.State.CONNECTING)
	await _hold()
	status._show(OnlineStatus.State.UNREACHABLE)
	await _hold()
	status._show(OnlineStatus.State.OLD_VERSION)
	await _hold()
	online.free()
	await get_tree().process_frame
	get_tree().quit()


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
