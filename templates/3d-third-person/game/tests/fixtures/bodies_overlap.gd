class_name BodiesOverlap
extends RefCounted
## Reads a clip file's `bodies_overlap.json` (kit #1286): how deep any body part goes inside
## another that no joint joins it to, on every frame of each clip, on each body's skinned mesh,
## as `assets/animation/limb_overlap.py --brief` measured it in Blender, with the SHA-256 of the
## clip file it measured. A test lists what crosses on a body (`problems`) against the limit, less
## the crossings it knows of (each with the issue that solves it).


## The report beside `clips` (a `res://` glb), or an empty one when there is none.
static func read(clips: String) -> Dictionary:
	var path := clips.get_base_dir().path_join("bodies_overlap.json")
	if not FileAccess.file_exists(path):
		return {}
	return JSON.parse_string(FileAccess.get_file_as_string(path))


## What is wrong with the report of `clips` for `bodies` (file names without `.glb`): a clip file
## that is not the one measured, a body or a clip not measured, and every crossing deeper than the
## report's limit that `known` (clip to body to millimetres) does not allow. A known crossing
## fails when it goes deeper than its number.
static func problems(clips: String, bodies: Array[String], known: Dictionary) -> Array[String]:
	var report := read(clips)
	if report.is_empty():
		return ["%s has no bodies_overlap.json beside it" % clips]
	var out: Array[String] = []
	if FileAccess.get_sha256(clips) != report.sha256:
		out.append("%s is not the file its bodies_overlap.json measured" % clips.get_file())
	var limit: float = report.limit_mm
	for clip: String in report.clips:
		var measured: Dictionary = report.clips[clip]
		for body in bodies:
			if not measured.has(body):
				out.append("%s was not measured on %s" % [clip, body])
				continue
			var entry: Dictionary = measured[body]
			var allowed: float = known.get(clip, {}).get(body, limit)
			if entry.deepest_mm > allowed:
				out.append(
					(
						"%s on %s: %s by %.1f mm at frame %s (allowed %.1f)"
						% [clip, body, entry.pair, entry.deepest_mm, entry.frame, allowed]
					)
				)
	return out
