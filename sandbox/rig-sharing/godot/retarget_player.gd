extends AnimationPlayer
## Plays shared clips on a character whose rest pose differs from the clip's source character.
##
## A clip that carries meta "src_rest" (bone name -> the source skeleton's rest position) has its position keys
## rebased onto this character: value - source rest + own rest. Clips without the meta play unchanged.


func _post_process_key_value(animation: Animation, track: int, value: Variant, object_id: int, object_sub_idx: int) -> Variant:
	if animation.track_get_type(track) != Animation.TYPE_POSITION_3D or not animation.has_meta("src_rest"):
		return value
	var sk := instance_from_id(object_id) as Skeleton3D
	if sk == null or object_sub_idx < 0:
		return value
	var src: Dictionary = animation.get_meta("src_rest")
	var bone := sk.get_bone_name(object_sub_idx)
	if not src.has(bone):
		return value
	return value - src[bone] + sk.get_bone_rest(object_sub_idx).origin
