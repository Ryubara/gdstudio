# The icon pool hands out icons and takes them back: after the busiest moment no icon is made again.
extends GdUnitTestSuite

var _parent: Control
var _pool: MinimapIconPool


func before_test() -> void:
	_parent = auto_free(Control.new()) as Control
	add_child(_parent)
	_pool = MinimapIconPool.new(load("res://ui/minimap/minimap_icon.tscn"), _parent)


func test_it_makes_an_icon_only_when_none_is_free() -> void:
	var first := _pool.acquire()
	_pool.release(first)
	var again := _pool.acquire()
	assert_object(again).is_same(first)
	assert_int(_pool.made()).is_equal(1)
	assert_int(_pool.in_use()).is_equal(1)


func test_a_released_icon_is_hidden_and_a_placed_one_shown() -> void:
	var icon := _pool.acquire()
	icon.place(null, Vector2(50.0, 40.0), 10.0, 0.0, Color.RED, 2)
	assert_bool(icon.visible).is_true()
	assert_vector(icon.position).is_equal(Vector2(45.0, 35.0))
	assert_int(icon.z_index).is_equal(2)
	_pool.release(icon)
	assert_bool(icon.visible).is_false()


func test_hundreds_of_icons_are_made_once() -> void:
	var out: Array[MinimapIcon] = []
	for i in 500:
		out.append(_pool.acquire())
	assert_int(_pool.made()).is_equal(500)
	for icon in out:
		_pool.release(icon)
	assert_int(_pool.in_use()).is_equal(0)
	for i in 500:
		_pool.acquire()
	assert_int(_pool.made()).is_equal(500)
	assert_int(_parent.get_child_count()).is_equal(500)


func test_prewarm_makes_icons_ahead_and_keeps_them_free() -> void:
	_pool.prewarm(40)
	assert_int(_pool.made()).is_equal(40)
	assert_int(_pool.in_use()).is_equal(0)
