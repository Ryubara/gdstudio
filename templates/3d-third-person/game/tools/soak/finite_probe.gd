class_name FiniteProbe
extends Node
## Temporary probe (kit #1326): every tick and every frame, the first Node3D whose global
## transform is not finite, the first skeleton bone pose that is not finite or not a rotation,
## and every engine error with its GDScript backtrace, printed as `FINITE_PROBE ...` lines.

var _nodes: Array[Node3D] = []
var _seen := {}
var _reported := 0
var _logger := Trace.new()


class Trace:
	extends Logger
	var count := 0

	func _log_error(
		function: String,
		file: String,
		line: int,
		code: String,
		rationale: String,
		_editor_notify: bool,
		error_type: int,
		backtraces: Array[ScriptBacktrace]
	) -> void:
		if error_type == ERROR_TYPE_WARNING:
			return
		count += 1
		if count > 6:
			return
		var text := (
			"FINITE_PROBE error f=%d %s %s:%d %s %s"
			% [Engine.get_physics_frames(), function, file, line, code, rationale]
		)
		for trace in backtraces:
			text += "\n" + trace.format()
		print(text)


func _enter_tree() -> void:
	OS.add_logger(_logger)
	process_physics_priority = 1 << 30
	process_priority = 1 << 30


func _exit_tree() -> void:
	OS.remove_logger(_logger)


func _ready() -> void:
	get_tree().node_added.connect(_on_added)
	_collect(get_tree().root)


func _collect(node: Node) -> void:
	_on_added(node)
	for child in node.get_children():
		_collect(child)


func _on_added(node: Node) -> void:
	if node is Node3D and not _seen.has(node.get_instance_id()):
		_seen[node.get_instance_id()] = true
		_nodes.append(node)


func _physics_process(_delta: float) -> void:
	_scan("tick")


func _process(_delta: float) -> void:
	_scan("frame")


func _scan(when: String) -> void:
	if _reported >= 4:
		return
	var kept: Array[Node3D] = []
	for node in _nodes:
		if not is_instance_valid(node):
			continue
		kept.append(node)
		if not node.is_inside_tree():
			continue
		var place := node.global_transform
		if not place.is_finite():
			_report(when, node, "global_transform %s local %s" % [place, node.transform])
		elif node is Skeleton3D:
			var skeleton := node as Skeleton3D
			for bone in skeleton.get_bone_count():
				var pose := skeleton.get_bone_pose(bone)
				var rotation := skeleton.get_bone_pose_rotation(bone)
				if not pose.is_finite() or not rotation.is_finite():
					_report(
						when,
						node,
						"bone %s pose %s rot %s" % [skeleton.get_bone_name(bone), pose, rotation]
					)
					break
	_nodes = kept


func _report(when: String, node: Node, what: String) -> void:
	_reported += 1
	var owner_character := node
	while owner_character != null and not owner_character is AiCharacter:
		owner_character = owner_character.get_parent()
	var about := ""
	if owner_character != null:
		var character := owner_character as AiCharacter
		about = (
			" character=%s dead=%s pos=%s vel=%s"
			% [character.name, character.is_dead(), character.global_position, character.velocity]
		)
		var controller := character.ai_controller()
		if controller != null:
			about += (
				" walk=%s aim=%s fire=%s"
				% [controller.walk_direction, controller.aim, controller.fire]
			)
	print(
		(
			"FINITE_PROBE bad %s f=%d t=%.3f node=%s %s%s"
			% [
				when,
				Engine.get_physics_frames(),
				Time.get_ticks_msec() / 1000.0,
				node.get_path(),
				what,
				about
			]
		)
	)
