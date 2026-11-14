class_name BodiesOverlap
extends RefCounted
## Reads a clip file's `bodies_overlap.json` (kit #1286): how deep any body part goes inside
## another that no joint joins it to, on every frame of each clip, on each body's skinned mesh,
## as `assets/animation/limb_overlap.py --brief` measured it in Blender, with the SHA-256 of the
## clip file it measured. A test lists what crosses on a body (`problems`) against the limit, less
## the crossings it knows of (each with the issue that solves it).
##
## The report also names what made its numbers (kit #1479, `assets/animation/measure_hash.py`):
## `measure_sha256`, the hash of the measure script's code, and `bodies_sha256`, each measured
## body file's. `stale` lists what is no longer what was measured, so a report fails until its
## numbers are read again once the script's code or a body changes.

## The measure whose code a report names.
const MEASURE := "res://assets/animation/limb_overlap.py"
## Where a body's file is, by the body's name (its file name without `.glb`).
const BODY_FOLDERS: Array[String] = [
	"res://assets/characters/prototype/", "res://assets/characters/mannequin/"
]


## The report beside `clips` (a `res://` glb), or an empty one when there is none: the clip file's
## own (`<name>_overlap.json`, for a folder with one clip file a body, kit #1293) or the folder's
## `bodies_overlap.json`.
static func read(clips: String) -> Dictionary:
	var path := clips.get_basename() + "_overlap.json"
	if not FileAccess.file_exists(path):
		path = clips.get_base_dir().path_join("bodies_overlap.json")
	if not FileAccess.file_exists(path):
		return {}
	return JSON.parse_string(FileAccess.get_file_as_string(path))


## What is wrong with the report of `clips` for `bodies` (file names without `.glb`): a clip file,
## a measure script or a body file that is not the one measured (`stale`), a body or a clip not
## measured, and every crossing deeper than the report's limit that `known` (clip to body to
## millimetres) does not allow. A known crossing fails when it goes deeper than its number.
static func problems(clips: String, bodies: Array[String], known: Dictionary) -> Array[String]:
	var report := read(clips)
	if report.is_empty():
		return ["%s has no overlap report beside it" % clips]
	var out: Array[String] = []
	if FileAccess.get_sha256(clips) != report.sha256:
		out.append("%s is not the file its overlap report measured" % clips.get_file())
	out.append_array(stale(report, bodies))
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


## What a report's numbers were not made by, as the game has it now: the measure script (`script`,
## by the hash of its code in `normal_form`) and the file of each of `bodies`. A report from
## before kit #1479 names neither and fails on both.
static func stale(
	report: Dictionary, bodies: Array[String], script: String = MEASURE
) -> Array[String]:
	var out: Array[String] = []
	var file: String = report.get("clips_file", "?")
	if report.get("measure_sha256", "") != code_sha256(FileAccess.get_file_as_string(script)):
		out.append(
			(
				"%s is not the script that measured %s's overlap report: measure it again"
				% [script.get_file(), file]
			)
		)
	var measured: Dictionary = report.get("bodies_sha256", {})
	for body in bodies:
		var path := body_file(body)
		if path.is_empty():
			out.append("%s has no file among the bodies" % body)
		elif measured.get(body, "") != FileAccess.get_sha256(path):
			out.append(
				(
					"%s is not the body %s's overlap report measured: measure it again"
					% [path.get_file(), file]
				)
			)
	return out


## The file of the body named `body`, or "" when no folder of bodies has it.
static func body_file(body: String) -> String:
	for folder in BODY_FOLDERS:
		if FileAccess.file_exists(folder + body + ".glb"):
			return folder + body + ".glb"
	return ""


## The SHA-256 of a Python source's normal form: what a report holds as `measure_sha256`.
static func code_sha256(text: String) -> String:
	return normal_form(text).sha256_text()


## A Python source's tokens with nothing that cannot change what it computes, exactly as
## `normal_form` of `assets/animation/measure_hash.py` makes it: no comment, no docstring (a
## triple-quoted string that starts a statement), no blank line, one space only between two names
## or numbers, no line break or indentation inside brackets. Each statement starts on its own
## line at its own indentation.
static func normal_form(text: String) -> String:
	var out := PackedStringArray()
	var depth := 0  # open brackets
	var fresh := true  # at the start of a statement: nothing of it is out yet
	var indent := 0
	var last := "\n"
	var i := 0
	var size := text.length()
	while i < size:
		var c := text[i]
		if c == "\n":
			if depth == 0:
				fresh = true
				indent = 0
			i += 1
		elif c == " " or c == "\t" or c == "\r":
			if fresh:
				indent += 1
			i += 1
		elif c == "#":
			while i < size and text[i] != "\n":
				i += 1
		else:
			var token := c
			if c == "'" or c == '"':
				var quote := c.repeat(3) if text.substr(i, 3) == c.repeat(3) else c
				var end := i + quote.length()
				while end < size and text.substr(end, quote.length()) != quote:
					end += 2 if text[end] == "\\" else 1
				end = mini(end + quote.length(), size)
				token = text.substr(i, end - i)
				if fresh and quote.length() == 3:
					i = end
					continue
			elif c in "([{":
				depth += 1
			elif c in ")]}":
				depth = maxi(depth - 1, 0)
			if fresh:
				out.append("\n" + " ".repeat(indent))
				fresh = false
			elif _word(last) and _word(token[0]) and not _word(text[i - 1]):
				out.append(" ")
			out.append(token)
			last = token[token.length() - 1]
			i += token.length()
	return "".join(out)


# A character of a name or a number: two tokens made of these need the space between them.
static func _word(c: String) -> bool:
	var code := c.unicode_at(0)
	return (
		c == "_"
		or code > 127
		or (code >= 48 and code <= 57)
		or (code >= 65 and code <= 90)
		or (code >= 97 and code <= 122)
	)
