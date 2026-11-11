@tool
class_name Crosshair
extends HudWidget
## The aiming reticle: a small filled circle in the middle of the screen with a thin, darker
## ring around it so it reads on bright and dark ground alike. It draws itself (no texture) and
## is placed by anchors, so it sits at the middle of the screen at any size; the editor always
## shows it, the game shows it only while the player aims, and never while the weapon in the hands
## says so (`WeaponDef.show_crosshair`, read every frame, so a change shows at once).
##
## The weapon aims through the middle of the viewport, which is where this node's middle is, so
## the circle is where the shot goes. It is a `HudWidget`, placed in the HUD's `Center` region,
## which is the whole screen and never inset by a phone's safe area.

@export_group("Look")
## The circle's radius.
@export_range(1.0, 40.0, 0.5, "suffix:px") var radius := 6.0:
	set(value):
		radius = value
		_resize()
## The circle's colour.
@export var color := Color(1.0, 1.0, 1.0, 1.0):
	set(value):
		color = value
		queue_redraw()
## The ring's colour: a dark, partly clear tone is subtle.
@export var outline_color := Color(0.04, 0.05, 0.08, 0.5):
	set(value):
		outline_color = value
		queue_redraw()
## The ring's width, outside the circle. Zero draws no ring.
@export_range(0.0, 8.0, 0.25, "suffix:px") var outline_width := 1.5:
	set(value):
		outline_width = value
		_resize()

@export_group("Show")
## On: the game shows the reticle only while the player aims. Off: it is always there. The editor
## always shows it.
@export var only_while_aiming := true:
	set(value):
		only_while_aiming = value
		update()

var _shown := false


func _ready() -> void:
	_resize()
	super()
	set_process(not Engine.is_editor_hint())


# A switch of weapon or a change to its `show_crosshair` sends no signal the part can hear, so it
# looks each frame and updates only when the answer changes.
func _process(_delta: float) -> void:
	if _has_data() != _shown:
		update()


func _draw() -> void:
	var middle := size / 2.0
	if outline_width > 0.0:
		draw_arc(
			middle, radius + outline_width / 2.0, 0.0, TAU, 48, outline_color, outline_width, true
		)
	draw_circle(middle, radius, color, true, -1.0, true)


func _on_bound(node: Node) -> void:
	refresh_on(node, &"aim_changed")


# It has something to show while the player aims, or always when it is told not to hide. A scene
# with no player keeps it only in the second case.
func _has_data() -> bool:
	return (
		(not only_while_aiming or (_bound != null and _bound.get(&"aiming") == true))
		and _weapon_shows_it()
	)


func _apply_visibility() -> void:
	if Engine.is_editor_hint():
		visible = true
		return
	super()
	_shown = _has_data()


# The weapon in the bound player's hands lets the crosshair show (none: it does).
func _weapon_shows_it() -> bool:
	var held: Weapon = _bound.get(&"weapon") as Weapon if _bound != null else null
	return held == null or held.definition == null or held.definition.show_crosshair


# The control is a square just big enough for the circle and its ring, growing from its middle
# (the anchors sit at the middle of the screen), so its offsets are half the edge each way.
func _resize() -> void:
	var half := radius + outline_width + 1.0
	offset_left = -half
	offset_top = -half
	offset_right = half
	offset_bottom = half
	queue_redraw()
