@tool
class_name Crosshair
extends Control
## The aiming reticle: a small filled circle in the middle of the screen with a thin, darker
## ring around it so it reads on bright and dark ground alike. It draws itself (no texture) and
## is placed by anchors, so it sits at the middle of the screen at any size; the editor always
## shows it, the game shows it only while the player aims.
##
## The weapon aims through the middle of the viewport, which is where this node's middle is, so
## the circle is where the shot goes.

@export_group("Nodes")
## The player whose aim shows the reticle. Empty looks for the node in the `player` group.
@export var player: Player

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
		_show_for_aim()

var _aiming := false


func _ready() -> void:
	_resize()
	if Engine.is_editor_hint():
		return
	if player == null:
		player = get_tree().get_first_node_in_group(Player.GROUP) as Player
	if player != null:
		player.aim_changed.connect(_on_aim_changed)
		_aiming = player.aiming
	_show_for_aim()


func _draw() -> void:
	var middle := size / 2.0
	if outline_width > 0.0:
		draw_arc(
			middle, radius + outline_width / 2.0, 0.0, TAU, 48, outline_color, outline_width, true
		)
	draw_circle(middle, radius, color, true, -1.0, true)


func _on_aim_changed(aiming: bool) -> void:
	_aiming = aiming
	_show_for_aim()


func _show_for_aim() -> void:
	if Engine.is_editor_hint():
		visible = true
		return
	visible = _aiming or not only_while_aiming


# The control is a square just big enough for the circle and its ring, growing from its middle
# (the anchors sit at the middle of the screen), so its offsets are half the edge each way.
func _resize() -> void:
	var half := radius + outline_width + 1.0
	offset_left = -half
	offset_top = -half
	offset_right = half
	offset_bottom = half
	queue_redraw()
