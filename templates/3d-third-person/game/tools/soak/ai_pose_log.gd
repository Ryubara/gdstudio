class_name AiPoseLog
extends Node
## The pose log of the AI soak (gdstudio #1345): every AI character's animation, a line each time
## what it plays changes (`POSE {json}`: the time, the character, its state, the locomotion node,
## the layers on with their clips and weights, the aim pitch the pose takes, its weapon, its
## director tier and whether its animation is throttled). Run it headless from the game folder:
## `godot --headless --path . --fixed-fps 60 res://tools/soak/ai_pose_log.tscn`. It runs the AI soak
## (`ai_soak.tscn`, its seed and counts set on the `Soak` node) and quits after `seconds` of
## simulated time.

## Simulated seconds it runs before it quits.
@export_range(1.0, 3600.0, 1.0, "suffix:s") var seconds := 60.0

var _last := {}
var _clock := 0.0


func _ready() -> void:
	get_tree().physics_frame.connect(_on_tick)


func _on_tick() -> void:
	_clock += 1.0 / Engine.physics_ticks_per_second
	if _clock >= seconds:
		get_tree().quit()
		return
	for node in get_tree().get_nodes_in_group(AiCharacter.GROUP):
		var character := node as AiCharacter
		if character == null or not character.is_inside_tree():
			continue
		var animation := _animation_of(character)
		if animation == null or animation.tree == null:
			continue
		var row := _row(character, animation)
		var key := character.get_instance_id()
		var signature := JSON.stringify(row)
		if _last.get(key, "") != signature:
			_last[key] = signature
			row["t"] = snappedf(_clock, 0.01)
			row["who"] = String(character.name)
			print("POSE ", JSON.stringify(row))


func _row(character: AiCharacter, animation: CharacterAnimation) -> Dictionary:
	var tree := animation.tree
	var row := {
		"state": Character.State.keys()[character.state],
		"body": String(animation.body_state()),
		"weapon": _weapon_name(character),
		"tier": character.tier,
		"throttled": animation.is_throttled(),
	}
	if character.is_dead():
		return row
	var layers := []
	if tree.get(&"parameters/Action/active"):
		layers.append("action:%s" % animation.last_action())
	if tree.get(&"parameters/Reload/active"):
		layers.append("reload")
	if tree.get(&"parameters/Shoot/active"):
		layers.append("shoot")
	if tree.get(&"parameters/Melee/active"):
		layers.append("melee")
	row["layers"] = layers
	row["armed"] = snappedf(float(tree.get(&"parameters/Armed/blend_amount")), 0.25)
	row["aimw"] = snappedf(float(tree.get(&"parameters/Aim/blend_amount")), 0.25)
	row["pose"] = snappedf(float(tree.get(&"parameters/AimPose/blend_position")), 15.0)
	row["active"] = tree.active
	return row


func _weapon_name(character: Character) -> String:
	if character.weapon == null or character.weapon.definition == null:
		return ""
	return character.weapon.definition.resource_path.get_file().get_basename()


static func _animation_of(character: Node) -> CharacterAnimation:
	for child in character.get_children():
		if child is CharacterAnimation:
			return child
	return null
