# The menu fit: on a phone the menu is laid out on a canvas half as big and drawn twice the size,
# so a button is a finger's size; elsewhere it is the parent's own size.
extends GdUnitTestSuite

var _parent: Control
var _fit: MenuFit


func before_test() -> void:
	_parent = auto_free(Control.new())
	_parent.size = Vector2(1920.0, 1080.0)
	_fit = MenuFit.new()
	_parent.add_child(_fit)
	add_child(_parent)


func test_forced_off_it_is_the_parents_size_at_scale_one() -> void:
	_fit.force = 1
	assert_vector(_fit.scale).is_equal(Vector2.ONE)
	assert_vector(_fit.size).is_equal(Vector2(1920.0, 1080.0))
	assert_float(_fit.factor()).is_equal(1.0)


func test_forced_on_it_is_half_the_parent_drawn_twice_as_big() -> void:
	_fit.force = 2
	assert_vector(_fit.scale).is_equal(Vector2(2.0, 2.0))
	assert_vector(_fit.size).is_equal(Vector2(960.0, 540.0))


func test_the_factor_is_a_setting() -> void:
	_fit.force = 2
	_fit.phone_factor = 3.0
	assert_vector(_fit.scale).is_equal(Vector2(3.0, 3.0))
	assert_vector(_fit.size).is_equal_approx(Vector2(640.0, 360.0), Vector2(0.01, 0.01))


func test_it_follows_the_parent_when_the_parent_is_resized() -> void:
	_fit.force = 2
	_parent.size = Vector2(2338.0, 1080.0)
	assert_vector(_fit.size).is_equal(Vector2(1169.0, 540.0))


func test_a_window_with_a_short_side_under_the_limit_is_a_phone() -> void:
	_fit.force = 0
	var window := get_window()
	var was := window.size
	window.size = Vector2i(844, 390)
	assert_float(_fit.factor()).is_equal(_fit.phone_factor)
	window.size = Vector2i(1920, 1080)
	var big := _fit.factor()
	window.size = was
	assert_float(big).is_equal(1.0 if not DisplayServer.is_touchscreen_available() else 2.0)
