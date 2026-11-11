# Where the HUD sits: the crosshair at the middle of the whole screen, the safe area's margin, the
# phone's scale, every part on screen and clear of the others and of the touch controls at phone
# and desktop sizes, and the parts that leave the thumbs' corners while the touch layer shows.
extends GdUnitTestSuite

var _scene: Node
var _hud: Hud
var _player: Player
var _window_size: Vector2i


func before_test() -> void:
	InputSim.release_all()
	# A headless window is 64 pixels square: give it a desktop's size, so the stretch is 2/3.
	_window_size = get_tree().root.size
	get_tree().root.size = Vector2i(1280, 720)
	_scene = scene_runner("res://main.tscn").scene()
	_hud = _scene.get_node("Hud")
	_player = _scene.get_node("PlayerRig/Player")
	await InputSim.ticks(get_tree(), 8)


func after_test() -> void:
	InputSim.release_all()
	get_tree().root.size = _window_size
	AudioDrain.stop_all(_scene)


func _region(region_name: StringName) -> Control:
	return _hud.region(region_name)


func test_the_crosshair_is_in_the_whole_screen_region_not_the_inset_one() -> void:
	var crosshair: Crosshair = _hud.root.get_node("Center/Crosshair")
	assert_bool(_hud.safe_area.is_ancestor_of(crosshair)).is_false()
	var view := _hud.get_viewport().get_visible_rect()
	assert_vector(crosshair.get_global_rect().get_center()).is_equal_approx(
		view.size / 2.0, Vector2.ONE * 0.6
	)


# A control's rectangle on the canvas, with the HUD's scale applied.
func _canvas_rect(control: Control) -> Rect2:
	var transform := control.get_global_transform()
	return Rect2(transform.origin, transform.basis_xform(control.size))


func test_the_safe_area_keeps_the_margin_from_the_screen_edge() -> void:
	var view := _hud.get_viewport().get_visible_rect()
	assert_float(_hud.root.scale.x).is_equal(1.0)
	var rect := _canvas_rect(_hud.safe_area)
	assert_vector(rect.position).is_equal_approx(Vector2.ONE * _hud.margin, Vector2.ONE * 0.6)
	assert_vector(view.end - rect.end).is_equal_approx(Vector2.ONE * _hud.margin, Vector2.ONE * 0.6)
	_hud.margin = 100.0
	assert_vector(_canvas_rect(_hud.safe_area).position).is_equal_approx(
		Vector2.ONE * 100.0, Vector2.ONE * 0.6
	)


# Gives the real HUD's health and ammo parts a subject that has data.
func _feed_the_parts() -> HudSubject:
	var subject := HudSubject.new()
	add_child(auto_free(subject))
	var weapon := HudSubjectWeapon.new()
	subject.add_child(weapon)
	subject.weapon = weapon
	for widget in _hud.widgets():
		if widget is HudStat:
			widget.player = subject
	subject.set_health(75.0)
	weapon.set_ammo(10)
	subject.revived.emit()
	_player.collect(&"coin", 12)
	_player.collect(&"gem", 3)
	return subject


func _visible_parts() -> Array[Control]:
	var found: Array[Control] = []
	for widget in _hud.widgets():
		if widget.visible and not widget is Crosshair:
			found.append(widget)
	return found


func _use_a_phone() -> void:
	get_tree().root.size = Vector2i(844, 390)
	await get_tree().process_frame
	await get_tree().process_frame


func test_the_hud_grows_on_a_phone_until_its_text_is_readable() -> void:
	_feed_the_parts()
	await _use_a_phone()
	var device_per_canvas := _hud.get_viewport().get_final_transform().get_scale().x
	var smallest := 26.0 * _hud.root.scale.x * device_per_canvas  # CSS pixels at a ratio of 1.
	assert_float(_hud.root.scale.x).is_greater(1.2)
	assert_float(smallest).is_greater_equal(_hud.min_text_size - 0.05)
	# A real phone has three device pixels to a CSS pixel and a canvas to match: the same size.
	_hud.pixel_ratio = 3.0
	get_tree().root.size = Vector2i(2532, 1170)
	await get_tree().process_frame
	await get_tree().process_frame
	var css := _hud.get_viewport().get_final_transform().get_scale().x / 3.0
	assert_float(26.0 * _hud.root.scale.x * css).is_greater_equal(_hud.min_text_size - 0.05)
	# A desktop's stays as it is.
	get_tree().root.size = Vector2i(1920, 1080)
	await get_tree().process_frame
	await get_tree().process_frame
	_hud.pixel_ratio = 1.0
	assert_float(_hud.root.scale.x).is_equal(1.0)


func test_every_part_is_on_screen_and_clear_of_the_others_at_phone_and_desktop_size() -> void:
	_feed_the_parts()
	for window in [
		Vector2i(1280, 720), Vector2i(844, 390), Vector2i(667, 375), Vector2i(2400, 1080)
	]:
		get_tree().root.size = window
		await get_tree().process_frame
		await get_tree().process_frame
		var view := _hud.get_viewport().get_visible_rect()
		var parts := _visible_parts()
		assert_int(parts.size()).is_equal(5)
		for first in parts.size():
			assert_bool(view.encloses(_canvas_rect(parts[first]))).is_true()
			for second in range(first + 1, parts.size()):
				(
					assert_bool(_canvas_rect(parts[first]).intersects(_canvas_rect(parts[second])))
					. is_false()
				)
		var crosshair: Crosshair = _hud.root.get_node("Center/Crosshair")
		assert_vector(_canvas_rect(crosshair).get_center()).is_equal_approx(
			view.size / 2.0, Vector2.ONE * 0.6
		)


# Every place of the weapon slots and the hotbar is at least a fingertip (44 CSS pixels) on a phone
# with the touch layer up, the slots go under the stick's resting ring and the hotbar under the
# health card (the bottom middle is too narrow between the thumbs on a 16:9 phone), and the places
# stand in one row each, in order.
func test_the_places_are_a_fingertip_on_a_phone_and_leave_the_thumbs_corner() -> void:
	var touch: TouchControls = _scene.get_node("PlayerRig/TouchControls")
	var slots: HudWeaponSlots = _region(&"BottomRight").get_node("HudWeaponSlots")
	var hotbar: HudHotbar = _region(&"BottomCenter").get_node("HudHotbar")
	touch.show_mode = TouchControls.ShowMode.ALWAYS
	touch._set_shown(true)
	assert_object(slots.get_parent()).is_same(_region(&"BottomLeft"))
	assert_object(hotbar.get_parent()).is_same(_region(&"TopLeft"))
	for window in [Vector2i(844, 390), Vector2i(667, 375)]:
		get_tree().root.size = window
		await get_tree().process_frame
		await get_tree().process_frame
		var css_per_canvas := _hud.css_height() / _hud.get_viewport().get_visible_rect().size.y
		var cells: Array[HudSlot] = slots.cells()
		cells.append_array(hotbar.cells())
		assert_int(cells.size()).is_equal(6)
		for cell in cells:
			var css := _canvas_rect(cell).size * css_per_canvas
			assert_float(minf(css.x, css.y)).is_greater_equal(44.0)
		for row: HudSlotRow in [slots, hotbar]:
			var places := row.cells()
			for index in range(1, places.size()):
				var left_rect := _canvas_rect(places[index - 1])
				var right_rect := _canvas_rect(places[index])
				assert_float(right_rect.position.x).is_greater_equal(left_rect.end.x)
				assert_float(right_rect.position.y).is_equal_approx(left_rect.position.y, 0.5)
	touch.show_mode = TouchControls.ShowMode.NEVER
	touch._set_shown(false)
	assert_object(slots.get_parent()).is_same(_region(&"BottomRight"))
	assert_object(hotbar.get_parent()).is_same(_region(&"BottomCenter"))


# Under the ammo card, so the card coming and going (the fists have none) never moves the slots.
func test_the_weapon_slots_stand_under_the_ammo_card_on_a_desktop() -> void:
	_feed_the_parts()
	var slots: HudWeaponSlots = _region(&"BottomRight").get_node("HudWeaponSlots")
	var ammo: HudStat = _region(&"BottomRight").get_node("HudAmmo")
	for window in [Vector2i(1280, 720), Vector2i(1920, 1080), Vector2i(2560, 1440)]:
		get_tree().root.size = window
		await get_tree().process_frame
		await get_tree().process_frame
		var slot_rect := _canvas_rect(slots.cells()[1])
		var ammo_rect := _canvas_rect(ammo)
		assert_float(slot_rect.position.y).is_greater_equal(ammo_rect.end.y)
		assert_float(slot_rect.end.x).is_equal_approx(ammo_rect.end.x, 1.0)


func test_the_touch_controls_move_the_bottom_parts_to_the_top_and_back() -> void:
	var touch: TouchControls = _scene.get_node("PlayerRig/TouchControls")
	_feed_the_parts()
	var health: HudStat = _region(&"BottomLeft").get_node("HudHealth")
	var ammo: HudStat = _region(&"BottomRight").get_node("HudAmmo")
	assert_bool(_hud.touch_layout).is_false()
	var event := InputEventScreenTouch.new()
	event.index = 9
	event.position = Vector2(5.0, 5.0)
	event.pressed = true
	touch._input(event)
	assert_bool(touch.is_shown()).is_true()
	assert_bool(_hud.touch_layout).is_true()
	assert_object(health.get_parent()).is_same(_region(&"TopLeft"))
	assert_object(ammo.get_parent()).is_same(_region(&"TopRight"))
	# Moved, a part still follows its data: the health it shows follows a hit.
	var subject: HudSubject = health.player
	subject.set_health(40.0)
	assert_str(health.value_label.text).is_equal("40 / 100")
	event.pressed = false
	touch._input(event)
	touch.show_mode = TouchControls.ShowMode.NEVER
	touch._set_shown(false)
	assert_bool(_hud.touch_layout).is_false()
	assert_object(health.get_parent()).is_same(_region(&"BottomLeft"))
	assert_object(ammo.get_parent()).is_same(_region(&"BottomRight"))


func test_no_part_is_under_a_touch_button_or_the_resting_stick_on_a_phone() -> void:
	var touch: TouchControls = _scene.get_node("PlayerRig/TouchControls")
	_feed_the_parts()
	touch.show_mode = TouchControls.ShowMode.ALWAYS
	touch._set_shown(true)
	assert_bool(_hud.touch_layout).is_true()
	for window in [Vector2i(844, 390), Vector2i(667, 375), Vector2i(1280, 720)]:
		get_tree().root.size = window
		await get_tree().process_frame
		await get_tree().process_frame
		var blocked: Array[Rect2] = []
		for index in touch.button_count():
			var reach := touch.button_size_of(index) / 2.0
			blocked.append(
				Rect2(touch.button_center(index) - Vector2.ONE * reach, Vector2.ONE * reach * 2.0)
			)
		var ring := touch.stick_radius
		blocked.append(Rect2(touch.stick_home() - Vector2.ONE * ring, Vector2.ONE * ring * 2.0))
		assert_int(_visible_parts().size()).is_equal(5)
		for part in _visible_parts():
			for rect in blocked:
				assert_bool(_canvas_rect(part).intersects(rect)).is_false()


func test_the_pause_and_bag_buttons_are_clear_of_the_minimap_and_the_parts_on_a_touch_screen(
) -> void:
	var touch: TouchControls = _scene.get_node("PlayerRig/TouchControls")
	var button: PauseButton = _scene.get_node("PlayerRig/MenuLayer/PauseButton")
	var bag: PauseButton = _scene.get_node("PlayerRig/MenuLayer/BagButton")
	var minimap: Minimap = _hud.get_node("Root/SafeArea/TopRight/MinimapSlot/Minimap")
	_feed_the_parts()
	touch.show_mode = TouchControls.ShowMode.ALWAYS
	touch._set_shown(true)
	assert_bool(button.visible).is_true()
	assert_bool(bag.visible).is_true()
	for window in [Vector2i(844, 390), Vector2i(667, 375), Vector2i(1280, 720)]:
		get_tree().root.size = window
		await get_tree().process_frame
		await get_tree().process_frame
		var others: Array[Control] = _visible_parts()
		others.append(minimap)
		for other in others:
			assert_bool(_canvas_rect(button).intersects(_canvas_rect(other))).is_false()
			assert_bool(_canvas_rect(bag).intersects(_canvas_rect(other))).is_false()
		assert_bool(_canvas_rect(bag).intersects(_canvas_rect(button))).is_false()
