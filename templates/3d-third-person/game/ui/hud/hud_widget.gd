@tool
class_name HudWidget
extends PanelContainer
## The base of every HUD part: it finds the player, lets a subclass connect to its signals, and
## shows itself only while it has something to show. A part is added by dropping its scene into one
## of the `Hud`'s regions; nothing else is wired.
##
## A subclass overrides these and never touches the tree itself:
## - `_on_bound(node)` connects what it listens to (use `refresh_on()`, which also lets go of the
##   connection when the player leaves);
## - `_has_data()` says whether the part has anything to show (the base: it has a player);
## - `_refresh()` writes the data into the part's nodes.
##
## A part whose data does not exist yet (no health on the player, no ammo on the weapon) is hidden
## and takes no room in its region, and it shows by itself the moment the data appears, so the
## weapon and hit-zone work only has to make the properties and signals exist.
##
## The part reads the player and never writes to it. Nothing here is sent over a network: a HUD
## belongs to the local screen.

## The part's data changed or went away; the `Hud` listens to place the part again.
signal data_changed

@export_group("Data")
## The node whose properties and signals feed the part. Empty looks for the first node of the
## `player` group when the scene starts (`rebind()` looks again).
@export var player: Node:
	set(value):
		player = value
		if is_node_ready() and not Engine.is_editor_hint():
			rebind()
## On: the part is hidden while it has no data. Off: it shows its resting text instead.
@export var hide_without_data := true:
	set(value):
		hide_without_data = value
		_apply_visibility()

@export_group("Phone")
## While the touch controls show, the `Hud` moves the part to this region, which is clear of the
## thumbs' corners (empty: it stays where it is).
@export_enum("", "TopLeft", "TopCenter", "TopRight", "BottomLeft", "BottomCenter", "BottomRight")
var touch_region := ""

var _bound: Node
var _links: Array[Array] = []


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	rebind()


func _exit_tree() -> void:
	if not Engine.is_editor_hint():
		_let_go()


## The node the part reads now (null: it has found no player).
func bound_to() -> Node:
	return _bound


## True while the part has something to show.
func has_data() -> bool:
	return _has_data()


## Looks for the player again (the `player` export, else the `player` group) and reads it afresh.
## Call it when the player is replaced.
func rebind() -> void:
	_let_go()
	var found := player
	if found == null and is_inside_tree():
		found = get_tree().get_first_node_in_group(Player.GROUP)
	if found != null and found.is_inside_tree():
		_bound = found
		found.tree_exiting.connect(_on_bound_leaving, CONNECT_ONE_SHOT)
		_on_bound(found)
	update()


## Reads the data into the part and shows or hides it.
func update() -> void:
	if not is_inside_tree():
		return
	if _has_data():
		_refresh()
	_apply_visibility()
	data_changed.emit()


## Calls `update` whenever `source` emits `signal_name`. A source without that signal is passed
## over, so a part can list signals a game has not made yet. The link ends with the binding.
func refresh_on(source: Object, signal_name: StringName) -> void:
	if source == null or not source.has_signal(signal_name):
		return
	var arguments := 0
	for entry in source.get_signal_list():
		if entry["name"] == signal_name:
			arguments = (entry["args"] as Array).size()
	var callable := update.unbind(arguments)
	if not source.is_connected(signal_name, callable):
		source.connect(signal_name, callable)
		_links.append([source, signal_name, callable])


## Override: connect to `node`'s signals here.
func _on_bound(_node: Node) -> void:
	pass


## Override: true when there is something to show. The base: a player is bound.
func _has_data() -> bool:
	return _bound != null


## Override: write the data into the part's nodes. Called only while `_has_data()` is true.
func _refresh() -> void:
	pass


func _apply_visibility() -> void:
	if Engine.is_editor_hint() or not is_inside_tree():
		return
	visible = _has_data() or not hide_without_data


func _on_bound_leaving() -> void:
	_let_go()
	update()


func _let_go() -> void:
	for link in _links:
		var source := link[0] as Object
		if is_instance_valid(source) and source.is_connected(link[1], link[2]):
			source.disconnect(link[1], link[2])
	_links.clear()
	if is_instance_valid(_bound) and _bound.tree_exiting.is_connected(_on_bound_leaving):
		_bound.tree_exiting.disconnect(_on_bound_leaving)
	_bound = null
