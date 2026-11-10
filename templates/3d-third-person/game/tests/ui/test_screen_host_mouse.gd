# The screen host watching the mouse, as a browser needs: a mouse the game held and lost opens the
# pause menu in that frame, Resume asks for it again, and a refusal does not open the menu again.
# The mouse is a stand-in platform: a headless run reads the mode back as visible.
extends GdUnitTestSuite

const PAUSE := preload("res://ui/menus/pause_menu.tscn")

var _host: ScreenHost
var _mode := Input.MOUSE_MODE_VISIBLE


func before_test() -> void:
	_mode = Input.MOUSE_MODE_VISIBLE
	_host = ScreenHost.new()
	_host.pause_screen = PAUSE
	_host.pause_on_focus_loss = false
	_host.mouse_mode_reader = func() -> Input.MouseMode: return _mode
	_host.mouse_mode_writer = func(mode: Input.MouseMode) -> void: _mode = mode
	add_child(_host)


func after_test() -> void:
	get_tree().paused = false
	await MenuFixture.clear(get_tree())
	if is_instance_valid(_host):
		_host.free()
	await get_tree().process_frame


func _settle() -> void:
	assert_bool(await MenuFixture.settle(get_tree())).is_true()


func test_losing_the_mouse_the_game_held_opens_the_pause_menu() -> void:
	_mode = Input.MOUSE_MODE_CAPTURED
	await get_tree().process_frame
	assert_bool(_host.is_open()).is_false()
	# A browser's first Esc: the pointer lock goes and the game never sees a key.
	_mode = Input.MOUSE_MODE_VISIBLE
	await get_tree().process_frame
	await _settle()
	assert_bool(_host.is_open()).is_true()
	assert_bool(get_tree().paused).is_true()
	assert_object(UIRouter.top()).is_instanceof(PauseMenu)


func test_the_mouse_lost_to_the_browser_is_asked_for_again_on_resume() -> void:
	_mode = Input.MOUSE_MODE_CAPTURED
	await get_tree().process_frame
	_mode = Input.MOUSE_MODE_VISIBLE
	await get_tree().process_frame
	await _settle()
	assert_bool(_host.is_open()).is_true()
	_host.close()
	await _settle()
	assert_int(_mode).is_equal(Input.MOUSE_MODE_CAPTURED)


func test_a_mouse_the_game_never_held_does_not_open_anything() -> void:
	for _frame in 5:
		await get_tree().process_frame
	assert_bool(_host.is_open()).is_false()
	assert_int(UIRouter.depth()).is_zero()


func test_the_lost_mouse_is_ignored_when_the_host_is_told_to() -> void:
	_host.pause_on_lost_mouse = false
	_mode = Input.MOUSE_MODE_CAPTURED
	await get_tree().process_frame
	_mode = Input.MOUSE_MODE_VISIBLE
	await get_tree().process_frame
	assert_bool(_host.is_open()).is_false()


func test_a_closed_menu_does_not_open_again_for_the_mouse_it_gave_back() -> void:
	_mode = Input.MOUSE_MODE_CAPTURED
	await get_tree().process_frame
	_host.open_pause()
	await _settle()
	# The browser refuses the lock for a moment after Esc: the mouse stays free after Resume.
	_host.mouse_mode_writer = func(_mode_given: Input.MouseMode) -> void: pass
	_mode = Input.MOUSE_MODE_VISIBLE
	_host.close()
	await _settle()
	for _frame in 5:
		await get_tree().process_frame
	assert_bool(_host.is_open()).is_false()
	assert_int(UIRouter.depth()).is_zero()
