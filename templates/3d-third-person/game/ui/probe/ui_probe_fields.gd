class_name UiProbeFields
extends RefCounted
## What the browser probes read of the menus: whether the game is paused, how many screens are up,
## the mouse mode, and where the control with the focus is (its middle, in canvas pixels, and its
## text), so a test that can only touch the page's pixels taps the right button of any screen.
## Written to the probe's object by `WebProbe` (in the game) and `MenuProbe` (in the menu scene).


## Writes the fields into `target`, a `JavaScriptObject`.
static func write(target: JavaScriptObject, viewport: Viewport) -> void:
	target.paused = viewport.get_tree().paused
	target.screens = UIRouter.depth()
	target.mouse_mode = int(Input.mouse_mode)
	var focus := viewport.gui_get_focus_owner()
	target.focus_name = str(focus.name) if focus != null else ""
	target.focus_text = (focus as Button).text if focus is Button else ""
	if focus != null:
		var centre := _middle(focus)
		target.focus_x = centre.x
		target.focus_y = centre.y
	else:
		target.focus_x = -1.0
		target.focus_y = -1.0
	# Where each visible button of the top screen is, as `btn_<its text>_x` and `_y`.
	var top := UIRouter.top()
	if top != null:
		for node in top.find_children("*", "Button", true, false):
			var button := node as Button
			if button.is_visible_in_tree() and button.text != "":
				var key := button.text.to_lower().strip_edges().replace(" ", "_")
				var middle := _middle(button)
				target.set("btn_%s_x" % key, middle.x)
				target.set("btn_%s_y" % key, middle.y)
	var settings := viewport.get_node_or_null("/root/Settings") as SettingsService
	if settings != null:
		target.volume_master = int(settings.get_value(SettingsService.VOLUME_MASTER))
		target.sensitivity = float(settings.get_value(SettingsService.MOUSE_SENSITIVITY))


## The middle of a control in canvas pixels, through its transform: a menu laid out at a phone's
## factor is a scaled control, and `get_global_rect()` does not carry the scale.
static func _middle(control: Control) -> Vector2:
	return control.get_global_transform() * (control.size * 0.5)
