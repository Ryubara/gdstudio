class_name TestUIRouterClose
extends GdUnitTestSuite
## UIRouter.close and clear: a menu over a game that is not a screen ends the stack empty.

const SETTLE_SECONDS := 4.0


func before_test() -> void:
	UIMotion.reduced = false
	UIRouter.reset(_screen("root"), UITransition.Kind.CUT)
	await _settle()


func after_test() -> void:
	await RouterFixture.clear(get_tree())


func test_close_ends_the_stack_empty_where_pop_stops_at_the_root() -> void:
	var changes := []
	UIRouter.screen_changed.connect(func(depth: int) -> void: changes.append(depth))
	UIRouter.close(UITransition.Kind.CUT)
	assert_bool(await _settle()).is_true()
	assert_int(UIRouter.depth()).is_equal(0)
	assert_array(changes).is_equal([0])


func test_close_with_two_screens_is_a_pop() -> void:
	UIRouter.push(_screen("b"), UITransition.Kind.CUT)
	UIRouter.close()
	assert_bool(await _settle()).is_true()
	assert_array(_names()).is_equal(["root"])


func test_close_fades_the_screen_out_and_frees_it() -> void:
	var root := UIRouter.top()
	UIRouter.close(UITransition.Kind.FADE)
	assert_bool(await _settle()).is_true()
	assert_int(UIRouter.depth()).is_equal(0)
	await get_tree().process_frame
	assert_bool(is_instance_valid(root)).is_false()


func test_clear_frees_every_screen() -> void:
	UIRouter.push(_screen("b"), UITransition.Kind.CUT)
	UIRouter.push(_screen("c"), UITransition.Kind.CUT)
	UIRouter.clear()
	assert_bool(await _settle()).is_true()
	assert_int(UIRouter.depth()).is_equal(0)
	UIRouter.clear()
	assert_bool(await _settle()).is_true()


func test_back_closes_the_only_screen_when_it_asks_for_it() -> void:
	var menu := UIScreen.new()
	menu.back_closes = true
	UIRouter.reset(menu, UITransition.Kind.CUT)
	assert_bool(await _settle()).is_true()
	_press_back()
	assert_bool(await _settle()).is_true()
	assert_int(UIRouter.depth()).is_equal(0)


func test_back_leaves_the_only_screen_that_does_not_close() -> void:
	UIRouter.reset(UIScreen.new(), UITransition.Kind.CUT)
	assert_bool(await _settle()).is_true()
	_press_back()
	assert_bool(await _settle()).is_true()
	assert_int(UIRouter.depth()).is_equal(1)


func test_a_screen_freed_while_it_closes_does_not_stall_the_router() -> void:
	var root := UIRouter.top()
	UIRouter.close(UITransition.Kind.FADE)
	await await_millis(20)
	root.free()
	assert_bool(await _settle()).is_true()
	assert_int(UIRouter.depth()).is_equal(0)


func _screen(screen_name: String) -> Control:
	var screen := Control.new()
	screen.name = screen_name
	screen.set_meta(&"label", screen_name)
	return screen


func _names() -> Array:
	return UIRouter.screens().map(func(screen: Control) -> String: return screen.get_meta(&"label"))


func _settle() -> bool:
	var waited := 0.0
	while UIRouter.busy and waited < SETTLE_SECONDS:
		await get_tree().process_frame
		waited += get_tree().root.get_process_delta_time()
	return not UIRouter.busy


func _press_back() -> void:
	var event := InputEventAction.new()
	event.action = &"ui_cancel"
	event.pressed = true
	UIRouter.get_viewport().push_input(event)
