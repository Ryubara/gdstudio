# The online overlay's card: in every state, at the desktop and the phone layout, the title, the
# message and the buttons sit inside the panel's row of bulbs, and the title is a title's size.
# The overlay is not under the router's stage, so this holds only once it has the tokens' theme.
extends GdUnitTestSuite

const SCENE := "res://ui/online/online_status.tscn"

var _status: OnlineStatus


func before_test() -> void:
	_status = auto_free(load(SCENE).instantiate())
	add_child(_status)
	# No client: the overlay would say "No server address" on its first frame. The test picks.
	_status.set_process(false)


func after_test() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _laid_out(state: OnlineStatus.State, phone: bool) -> void:
	(_status.get_node("Root/Fit") as MenuFit).force = 2 if phone else 1
	_status._show(state)
	await await_idle_frame()
	await await_idle_frame()


## The rectangles of the column's shown parts, in the panel's own units.
func _parts() -> Dictionary:
	var column: Control = _status.get_node("%Panel/Column")
	var parts := {}
	for child in column.get_children():
		var part := child as Control
		if part.visible:
			parts[part.name] = Rect2(column.position + part.position, part.size)
	return parts


## Inside the bulbs: the panel less the inset the bulbs are drawn on and a bulb's radius.
func _inside_the_bulbs() -> Rect2:
	var panel: UIPanel = _status.get_node("%Panel")
	var tokens := UITokens.active()
	return Rect2(Vector2.ZERO, panel.size).grow(-(tokens.space_md + tokens.bulb_radius))


func _assert_clear_of_the_bulbs(state: OnlineStatus.State, phone: bool) -> void:
	await _laid_out(state, phone)
	var inside := _inside_the_bulbs()
	var parts := _parts()
	assert_bool(parts.is_empty()).is_false()
	for part: StringName in parts:
		var rect: Rect2 = parts[part]
		(
			assert_bool(inside.encloses(rect))
			. override_failure_message(
				(
					"%s %s runs into the bulbs %s (state %d, phone %s)"
					% [part, rect, inside, state, phone]
				)
			)
			. is_true()
		)


func test_connecting_reads_clear_of_the_bulbs_on_a_desktop_and_a_phone() -> void:
	await _assert_clear_of_the_bulbs(OnlineStatus.State.CONNECTING, false)
	await _assert_clear_of_the_bulbs(OnlineStatus.State.CONNECTING, true)


func test_a_message_with_back_to_menu_reads_clear_of_the_bulbs() -> void:
	for state: OnlineStatus.State in [
		OnlineStatus.State.UNREACHABLE, OnlineStatus.State.OLD_VERSION, OnlineStatus.State.LOST
	]:
		await _assert_clear_of_the_bulbs(state, false)
		await _assert_clear_of_the_bulbs(state, true)


func test_the_title_is_a_title_and_the_panel_padded_from_the_tokens() -> void:
	await _laid_out(OnlineStatus.State.CONNECTING, false)
	var tokens := UITokens.active()
	var title: Label = _status.get_node("%Title")
	assert_int(title.get_theme_font_size(&"font_size")).is_equal(tokens.size_title)
	var panel: UIPanel = _status.get_node("%Panel")
	var box := panel.get_theme_stylebox(&"panel")
	assert_float(box.content_margin_top).is_equal(float(tokens.space_lg))
	assert_float(box.content_margin_left).is_equal(float(tokens.space_xl))
