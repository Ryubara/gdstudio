# The character's touch layer: the base's touch controls with three more buttons (fire, aim and
# crouch) as nodes of their own scene. A finger on each presses its action, and the player
# crouches, aims and shoots from them.
extends GdUnitTestSuite

const SCENE := "res://ui/touch/third_person_touch_controls.tscn"

var _scene: Node
var _touch: TouchControls
var _player: Player


func before_test() -> void:
	_scene = scene_runner("res://main.tscn").scene()
	_touch = _scene.get_node("TouchControls")
	_player = _scene.get_node("Player")
	await InputSim.ticks(get_tree(), 8)


func after_test() -> void:
	InputSim.release_all()
	AudioDrain.stop_all(_scene)


func _button(button_name: String) -> TouchButton:
	return _touch.buttons_root.get_node(button_name)


func _index(button_name: String) -> int:
	return _button(button_name).get_index()


func _touch_event(index: int, at: Vector2, pressed: bool) -> void:
	var event := InputEventScreenTouch.new()
	event.index = index
	event.position = at
	event.pressed = pressed
	_touch._input(event)


func test_the_scene_adds_three_buttons_to_the_base_and_keeps_its_two() -> void:
	var packed := load(SCENE) as PackedScene
	var inherited := auto_free(packed.instantiate()) as TouchControls
	add_child(inherited)
	await get_tree().process_frame
	assert_int(inherited.button_count()).is_equal(5)
	var actions := {}
	for button in inherited.buttons_root.get_children():
		actions[(button as TouchButton).action] = (button as TouchButton).label
	assert_dict(actions).is_equal(
		{&"jump": "Jump", &"interact": "Use", &"fire": "Fire", &"aim": "Aim", &"crouch": "Crouch"}
	)
	assert_array(inherited._get_configuration_warnings()).is_empty()


func test_the_new_buttons_do_not_cover_each_other_or_the_old_ones() -> void:
	var rects: Array[Rect2] = []
	for button in _touch.buttons_root.get_children():
		rects.append((button as TouchButton).get_global_rect())
	for first in rects.size():
		for second in range(first + 1, rects.size()):
			(
				assert_bool(rects[first].intersects(rects[second]))
				. override_failure_message("buttons %d and %d overlap" % [first, second])
				. is_false()
			)
	var view := _touch.get_viewport().get_visible_rect()
	for rect in rects:
		assert_bool(view.encloses(rect)).is_true()


func test_a_finger_on_the_crouch_button_crouches_and_lifting_it_stands() -> void:
	var at := _touch.button_center(_index("Crouch"))
	_touch_event(5, at, true)
	await InputSim.ticks(get_tree(), 20)
	assert_bool(Input.is_action_pressed(&"crouch")).is_true()
	assert_bool(_player.crouching).is_true()
	assert_bool(_button("Crouch").held).is_true()
	_touch_event(5, at, false)
	await InputSim.ticks(get_tree(), 30)
	assert_bool(_player.crouching).is_false()


func test_a_finger_on_the_aim_button_aims_and_shows_the_crosshair() -> void:
	var at := _touch.button_center(_index("Aim"))
	_touch_event(5, at, true)
	await InputSim.ticks(get_tree(), 10)
	assert_bool(_player.aiming).is_true()
	assert_bool((_scene.get_node("Hud/Crosshair") as Control).visible).is_true()
	_touch_event(5, at, false)
	await InputSim.ticks(get_tree(), 10)
	assert_bool(_player.aiming).is_false()
	assert_bool((_scene.get_node("Hud/Crosshair") as Control).visible).is_false()


func test_a_finger_on_the_fire_button_shoots_and_two_fingers_aim_and_fire() -> void:
	var shots := []
	_player.weapon.fired.connect(func(shot: Projectile) -> void: shots.append(shot))
	_touch_event(5, _touch.button_center(_index("Aim")), true)
	await InputSim.ticks(get_tree(), 20)
	_touch_event(6, _touch.button_center(_index("Fire")), true)
	await InputSim.ticks(get_tree(), 20)
	assert_array(shots).has_size(1)
	assert_bool(_player.aiming).is_true()
	_touch_event(6, _touch.button_center(_index("Fire")), false)
	await InputSim.ticks(get_tree(), 20)
	_touch_event(6, _touch.button_center(_index("Fire")), true)
	await InputSim.ticks(get_tree(), 20)
	assert_array(shots).has_size(2)
