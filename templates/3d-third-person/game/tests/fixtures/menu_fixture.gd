class_name MenuFixture
extends RefCounted
## What the menu suites share: an empty router before and after a test, a wait for the router, and
## a walk over the focus a key or a pad would make.

const SETTLE_SECONDS := 4.0


## Frees every screen on the router, top first, and waits until it has settled. A screen left on
## the router covers the mouse for every suite after it.
static func clear(tree: SceneTree) -> void:
	await tree.process_frame
	if UIRouter.busy:
		await UIRouter.idle
	var screens := UIRouter.screens()
	screens.reverse()
	for screen in screens:
		if is_instance_valid(screen):
			screen.free()
	await tree.process_frame
	await tree.process_frame


## Waits until the router has drained its queue; false when it is still busy after the limit.
static func settle(tree: SceneTree) -> bool:
	var waited := 0.0
	while UIRouter.busy and waited < SETTLE_SECONDS:
		await tree.process_frame
		waited += tree.root.get_process_delta_time()
	await tree.process_frame
	await tree.process_frame
	return not UIRouter.busy


## Every control under `root` that takes focus and is on screen.
static func focusables(root: Node) -> Array[Control]:
	var found: Array[Control] = []
	for node in root.find_children("*", "Control", true, false):
		var control := node as Control
		if control.focus_mode != Control.FOCUS_ALL or not control.is_visible_in_tree():
			continue
		if control is BaseButton and (control as BaseButton).disabled:
			continue
		found.append(control)
	return found


## The controls a player reaches from `start` by pressing the four directions, as the engine
## chooses them (`find_valid_focus_neighbor`), including the steps the screen set by hand.
static func reachable(start: Control) -> Array[Control]:
	var seen: Array[Control] = [start]
	var queue: Array[Control] = [start]
	while not queue.is_empty():
		var control: Control = queue.pop_front()
		for side: Side in [SIDE_TOP, SIDE_BOTTOM, SIDE_LEFT, SIDE_RIGHT]:
			var next := control.find_valid_focus_neighbor(side)
			if next != null and next not in seen:
				seen.append(next)
				queue.append(next)
	return seen


## Sends a press and a release of an action's first event through the input path.
static func press_action(action: StringName) -> void:
	for event in InputMap.action_get_events(action):
		var press := event.duplicate() as InputEvent
		_set_pressed(press, true)
		Input.parse_input_event(press)
		Input.flush_buffered_events()
		var release := event.duplicate() as InputEvent
		_set_pressed(release, false)
		Input.parse_input_event(release)
		Input.flush_buffered_events()
		return


static func _set_pressed(event: InputEvent, pressed: bool) -> void:
	if event is InputEventKey:
		(event as InputEventKey).pressed = pressed
	elif event is InputEventJoypadButton:
		(event as InputEventJoypadButton).pressed = pressed
	elif event is InputEventJoypadMotion:
		(event as InputEventJoypadMotion).axis_value = (
			(event as InputEventJoypadMotion).axis_value if pressed else 0.0
		)
