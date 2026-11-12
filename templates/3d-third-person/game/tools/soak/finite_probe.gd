class_name FiniteProbe
extends Node
## Temporary probe (kit #1326): every tick and every frame, the first Node3D whose global
## transform is not finite, the first skeleton bone pose that is not finite or not a rotation,
## and every engine error with its GDScript backtrace, printed as `FINITE_PROBE ...` lines.

var _nodes: Array[Node3D] = []
var _seen := {}
var _reported := 0
var _logger := Trace.new()
var _hits := {}
var _before := {}
var _rings := {}
var _flinch := {}
var _flinches := 0
var _restarts := 0
var _wild := 0


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
	print("FINITE_PROBE flinches=%d restarts=%d wild=%d" % [_flinches, _restarts, _wild])


func _ready() -> void:
	get_tree().node_added.connect(_on_added)
	_collect(get_tree().root)


func _collect(node: Node) -> void:
	_on_added(node)
	for child in node.get_children():
		_collect(child)


func _on_added(node: Node) -> void:
	if node is Character and not node.hit_received.is_connected(_on_hit):
		node.hit_received.connect(_on_hit.bind(node))
	if node is HitReaction and not node.flinched.is_connected(_on_flinched):
		node.flinched.connect(_on_flinched.bind(node))
		node.flinch_ended.connect(_on_flinch_ended.bind(node))
	if node is Node3D and not _seen.has(node.get_instance_id()):
		_seen[node.get_instance_id()] = true
		_nodes.append(node)


func _on_flinch_ended(reaction: HitReaction) -> void:
	if _flinch.has(reaction.get_instance_id()):
		_flinch[reaction.get_instance_id()].live = false


func _on_flinched(bones: Array[StringName], reaction: HitReaction) -> void:
	_flinches += 1
	var key := reaction.get_instance_id()
	var restart: bool = _flinch.has(key) and _flinch[key].live
	_restarts += 1 if restart else 0
	_flinch[key] = {
		"live": true,
		"start": Engine.get_physics_frames(),
		"restart": restart,
		"told": false,
		"bones": bones,
		"pooled": not String(reaction.ragdoll.simulator().name).begins_with("Ragdoll")
	}


func _on_hit(record: HitRecord, character: Node) -> void:
	_hits[character.get_instance_id()] = (
		"f=%d bone=%s point=%s dir=%s strength=%s killed=%s"
		% [
			Engine.get_physics_frames(),
			record.bone,
			record.point,
			record.direction,
			record.strength,
			record.killed
		]
	)


func _physics_process(_delta: float) -> void:
	_record_flinches()
	_scan("tick")


# The last ticks of every flinching character's flinch bodies, dumped at the first bad value.
func _record_flinches() -> void:
	for node in get_tree().get_nodes_in_group(AiCharacter.GROUP):
		var reaction := node.find_child("HitReaction", true, false)
		if reaction == null or not reaction.is_flinching():
			continue
		var ragdoll: CharacterRagdoll = reaction.ragdoll
		var sim := ragdoll.simulator()
		var state: Dictionary = _flinch.get(reaction.get_instance_id(), {})
		var most := 0.0
		var worst := &""
		for key: StringName in reaction.flinch_bones():
			var off := ragdoll.body(key).global_position.distance_to(
				ragdoll.animated_body(key).origin
			)
			if not off <= most:
				most = off
				worst = key
		if not state.is_empty() and not state.told and not most < 0.25:
			state.told = true
			_wild += 1
			print(
				(
					"FINITE_PROBE wild f=%d after=%d restart=%s pooled=%s worst=%s off=%.3f char=%s bones=%s"
					% [
						Engine.get_physics_frames(),
						Engine.get_physics_frames() - state.start,
						state.restart,
						state.pooled,
						worst,
						most,
						node.name,
						state.bones
					]
				)
			)
		var line := (
			"f=%d infl=%.3f active=%s simulating=%s skel_scale=%s"
			% [
				Engine.get_physics_frames(),
				sim.influence,
				sim.active,
				sim.is_simulating_physics(),
				ragdoll.model.skeleton().global_transform.basis.get_scale()
			]
		)
		for entry: Dictionary in CharacterRagdoll.BODIES:
			var bone := ragdoll.body(entry.bone)
			if bone == null:
				continue
			var anim := ragdoll.animated_body(entry.bone)
			line += (
				"\n   %s sim=%s at=%s q=%s det=%.6f v=%s w=%s anim_at=%s anim_det=%.6f"
				% [
					entry.bone,
					bone.is_simulating_physics(),
					bone.global_position,
					bone.global_basis.get_rotation_quaternion(),
					bone.global_basis.determinant(),
					bone.linear_velocity,
					bone.angular_velocity,
					anim.origin,
					anim.basis.determinant()
				]
			)
		var ring: Array = _rings.get(node.get_instance_id(), [])
		ring.append(line)
		if ring.size() > 4:
			ring.remove_at(0)
		_rings[node.get_instance_id()] = ring


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
			var extra := ""
			if node is PhysicalBone3D:
				var bone := node as PhysicalBone3D
				extra = (
					" sim=%s v=%s w=%s before=%s"
					% [
						bone.is_simulating_physics(),
						bone.linear_velocity,
						bone.angular_velocity,
						_before.get(node.get_instance_id(), "?")
					]
				)
			_report(when, node, "global_transform %s%s" % [place, extra])
		elif node is PhysicalBone3D and when == "tick":
			var bone := node as PhysicalBone3D
			_before[node.get_instance_id()] = (
				"f=%d sim=%s at=%s v=%s w=%s"
				% [
					Engine.get_physics_frames(),
					bone.is_simulating_physics(),
					place.origin,
					bone.linear_velocity,
					bone.angular_velocity
				]
			)
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
	if _reported >= 4:
		return
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
		about += " last_hit=%s" % _hits.get(character.get_instance_id(), "none")
		var reaction := character.find_child("HitReaction", true, false)
		if reaction != null:
			about += " flinching=%s bones=%s" % [reaction.is_flinching(), reaction.flinch_bones()]
		var controller := character.ai_controller()
		if controller != null:
			about += (
				" walk=%s aim=%s fire=%s"
				% [controller.walk_direction, controller.aim, controller.fire]
			)
	if owner_character != null and _reported == 1:
		for line: String in _rings.get(owner_character.get_instance_id(), []):
			print("FINITE_PROBE ring " + line)
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
