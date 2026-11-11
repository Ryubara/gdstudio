@tool
extends EditorScenePostImport
## The import script of the prototype mannequins (kit #1149): what a `.glb` cannot hold itself.
##
## Set as each model's `import_script/path`, it runs when Godot imports the file and
## - sets `Skeleton3D.motion_scale` to the body's hips height over the clip library's, so the
##   hips' position keys of every clip fit a body of any leg length;
## - adds a `MannequinTwist` under the skeleton, which turns the twist bones;
## - shows `Body_LOD0`, `Body_LOD1` and `Body_LOD2` by distance (visibility ranges).
## A body built by `build_mannequins.py` for a game of your own gets the same by pointing its
## import at this script.

## The hips height (m) the clip libraries key the `pelvis` for (`skeleton.py`).
const REFERENCE_HIPS := 0.916607
## The distance (m) from which each level of detail shows, and the overlap that stops a
## character at the edge from flickering between two.
const LOD_DISTANCE: Array[float] = [0.0, 9.0, 22.0]
const LOD_MARGIN := 0.75

const TWIST := preload("res://assets/characters/prototype/mannequin_twist.gd")


func _post_import(scene: Node) -> Object:
	var found := scene.find_children("*", "Skeleton3D", true, false)
	if found.is_empty():
		return scene
	var skeleton: Skeleton3D = found[0]
	var pelvis := skeleton.find_bone("pelvis")
	if pelvis >= 0:
		skeleton.motion_scale = skeleton.get_bone_global_rest(pelvis).origin.y / REFERENCE_HIPS
	if skeleton.find_bone("lowerarm_twist_01_l") >= 0:
		var twist := TWIST.new()
		twist.name = "MannequinTwist"
		skeleton.add_child(twist)
		twist.owner = scene
	for level in LOD_DISTANCE.size():
		var mesh := skeleton.get_node_or_null("Body_LOD%d" % level) as MeshInstance3D
		if mesh == null:
			continue
		mesh.visibility_range_begin = LOD_DISTANCE[level]
		mesh.visibility_range_begin_margin = LOD_MARGIN if level > 0 else 0.0
		if level + 1 < LOD_DISTANCE.size():
			mesh.visibility_range_end = LOD_DISTANCE[level + 1]
			mesh.visibility_range_end_margin = LOD_MARGIN
	return scene
