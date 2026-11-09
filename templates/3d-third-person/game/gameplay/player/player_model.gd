@tool
class_name PlayerModel
extends Node3D
## The slot of the player's 3D model. It stays in the scene when the model is replaced, so
## nothing else points at the model itself: the model is one child (a `.glb` of the Quaternius
## universal rig) and this node finds its `Skeleton3D`.
##
## To swap the character in the editor, delete the old model child, drag the new `.glb` onto this
## node, and save. Every `BoneAttachment3D` child (the pistol in the hand) is seated on the new
## skeleton, and `rig_changed` tells the `PlayerAnimation` to point the clips at it, so nothing
## is set again by hand. The `Player` turns this node to face its heading, so the model's
## +Z is forward.

## The model child changed (a new one was added, or the old one left). `rig` is the new one, or
## null while there is none.
signal rig_changed(rig: Node3D)

var _rig: Node3D
var _skeleton: Skeleton3D
var _announced: Node3D
var _queued := false


func _ready() -> void:
	_refresh()
	child_entered_tree.connect(_on_children_changed.unbind(1))
	child_exiting_tree.connect(_on_child_exiting)


## The model: the first child that holds a `Skeleton3D`, or null.
func rig() -> Node3D:
	if _rig == null or not is_instance_valid(_rig) or _rig.get_parent() != self:
		_find()
	return _rig


## The skeleton of the model, or null.
func skeleton() -> Skeleton3D:
	rig()
	return _skeleton


func _on_child_exiting(child: Node) -> void:
	# Let go of the skeleton while it still exists: the attachment unbinds from it, and from a
	# skeleton that is already freed the engine logs an error.
	if child == _rig:
		for seat in get_children():
			if seat is BoneAttachment3D:
				seat.set_external_skeleton(NodePath())
	_on_children_changed()


func _on_children_changed() -> void:
	# A child that leaves is still listed during the signal, and a child that enters has not
	# set its owner yet, so look again on the next idle frame.
	if not _queued:
		_queued = true
		_refresh.call_deferred()


func _refresh() -> void:
	_queued = false
	_find()
	_seat_attachments()
	update_configuration_warnings()
	# Compared with the last one announced, not with the last one found: `rig()` finds it too, and
	# the editor asks for it whenever it lists the scene's warnings.
	if _rig != _announced:
		_announced = _rig
		rig_changed.emit(_rig)


func _find() -> void:
	_rig = null
	_skeleton = null
	for child in get_children():
		if child.is_queued_for_deletion() or not child is Node3D:
			continue
		var found := child.find_children("*", "Skeleton3D", true, false)
		if not found.is_empty():
			_rig = child
			_skeleton = found[0]
			return


# Every `BoneAttachment3D` child hangs on the model's skeleton by a path this node writes, as
# the engine clears a path when the node it points at is deleted.
#
# Writing the path is not enough. The engine connects an attachment to its skeleton's
# `skeleton_updated` signal when it enters the tree and whenever `use_external_skeleton` or
# `bone_name` is set, and remembers that it is connected. Setting the path changes where it looks
# and neither disconnects nor connects. When the model is swapped at run time the old skeleton is
# freed with the attachment still marked connected, so the new skeleton is never connected and the
# pistol stays where the old hand last was. The setters first let go of the skeleton the path points
# at, so they run with the path empty (nothing to disconnect from) to clear the mark, and after the
# path is written to connect. Run with the new path while the mark is stale, they disconnect from
# the new skeleton, which has no connection to it, and the engine logs an error.
func _seat_attachments() -> void:
	if _skeleton == null or not is_inside_tree():
		return
	for child in get_children():
		var seat := child as BoneAttachment3D
		if seat == null or _is_seated(seat):
			continue
		seat.set_external_skeleton(NodePath())
		seat.use_external_skeleton = true
		seat.set_external_skeleton(seat.get_path_to(_skeleton))
		# Looks the bone up again by its name on this skeleton (a model may order its bones
		# differently, and one without the bone gets no connection) and connects.
		seat.bone_name = seat.bone_name


# The attachment looks for this model's skeleton and is connected to its `skeleton_updated`.
func _is_seated(seat: BoneAttachment3D) -> bool:
	if not seat.use_external_skeleton:
		return false
	if seat.get_node_or_null(seat.get_external_skeleton()) != _skeleton:
		return false
	for connection in _skeleton.get_signal_connection_list(&"skeleton_updated"):
		if connection["callable"].get_object() == seat:
			return true
	return false


func _get_configuration_warnings() -> PackedStringArray:
	var warnings := PackedStringArray()
	var rigs := 0
	for child in get_children():
		if child is Node3D and not child.find_children("*", "Skeleton3D", true, false).is_empty():
			rigs += 1
	if rigs == 0:
		warnings.append("Add the character's model (a .glb with a Skeleton3D) as a child.")
	elif rigs > 1:
		warnings.append("More than one model: delete the one that is not used.")
	return warnings
