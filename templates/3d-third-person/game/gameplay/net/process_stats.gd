class_name ProcessStats
extends RefCounted
## The server process's own resident memory and processor share, for `NetServer`'s `stats` line:
## read from Linux's procfs (`/proc/self/status`, `/proc/self/stat`), so a server in its Docker
## image or on Railway reports what it costs. Elsewhere (Windows, macOS) `sample()` is empty.
## procfs files report a length of 0, so they are read line by line, never with `get_as_text()`
## (kit docs: engines/godot/multiplayer.md#headless-server-image).

## The clock ticks a second of the times in /proc/self/stat (Linux's USER_HZ, 100 by its ABI).
const USER_HZ := 100.0

var status_path := "/proc/self/status"
var stat_path := "/proc/self/stat"

var _ticks := -1
var _ticks_at_usec := 0


## `rss_mb`: the resident memory in megabytes, of which `anon_mb` is the process's own (the rest
## is the Godot program's mapped file, shared and reloadable: what a container's memory counts is
## close to `anon_mb`); `cpu_pct`: the share of one core since the last sample, in percent (from
## the second sample on). Each is left out when it cannot be read.
func sample(now_usec: int = Time.get_ticks_usec()) -> Dictionary:
	var out := {}
	var rss := status_kb(_first_line_with(status_path, "VmRSS:"), "VmRSS:")
	if rss >= 0:
		out["rss_mb"] = snappedf(rss / 1024.0, 0.1)
	var anon := status_kb(_first_line_with(status_path, "RssAnon:"), "RssAnon:")
	if anon >= 0:
		out["anon_mb"] = snappedf(anon / 1024.0, 0.1)
	var ticks := cpu_ticks(_first_line_with(stat_path, ""))
	if ticks >= 0:
		if _ticks >= 0 and now_usec > _ticks_at_usec:
			var seconds := (now_usec - _ticks_at_usec) / 1000000.0
			out["cpu_pct"] = snappedf((ticks - _ticks) / USER_HZ / seconds * 100.0, 0.1)
		_ticks = ticks
		_ticks_at_usec = now_usec
	return out


## The kilobytes of a /proc/self/status line such as `VmRSS:   184320 kB` whose key is `key`
## (with its colon), or -1.
static func status_kb(line: String, key: String) -> int:
	if not line.begins_with(key):
		return -1
	var number := line.get_slice(":", 1).strip_edges().get_slice(" ", 0)
	return int(number) if number.is_valid_int() else -1


## The user and system clock ticks of a /proc/self/stat line, or -1. The name (field 2) is in
## parentheses and may hold spaces, so the fields are counted after its last `)`: state is the
## first there, utime (field 14) the 12th and stime (field 15) the 13th.
static func cpu_ticks(line: String) -> int:
	var close := line.rfind(")")
	if close < 0:
		return -1
	var fields := line.substr(close + 1).strip_edges().split(" ", false)
	if fields.size() < 13 or not fields[11].is_valid_int() or not fields[12].is_valid_int():
		return -1
	return int(fields[11]) + int(fields[12])


# The first line of `path` that starts with `prefix` ("" for the first line), or "".
static func _first_line_with(path: String, prefix: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	while file != null and not file.eof_reached():
		var line := file.get_line()
		if line.begins_with(prefix):
			return line
	return ""
