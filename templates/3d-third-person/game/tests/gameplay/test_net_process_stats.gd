# ProcessStats: the server's memory and processor share read from Linux's procfs, here from
# copies of its two files (the suites also run on Windows, which has no /proc).
extends GdUnitTestSuite

const STATUS := "Name:\tgodot\nVmPeak:\t  210000 kB\nVmRSS:\t  151612 kB\nRssAnon:\t   78900 kB\n"
# A name with a space and a parenthesis: the fields are counted after the last `)`.
const STAT := "7 (godot (x) y) S 1 7 7 0 -1 4194560 9000 0 0 0 250 50 0 0 20 0 20 0 300 0 0"

var _dir := ""


func before_test() -> void:
	_dir = "user://test_net_process_stats_%d" % OS.get_process_id()
	DirAccess.make_dir_recursive_absolute(_dir)


func after_test() -> void:
	for file in DirAccess.get_files_at(_dir):
		DirAccess.remove_absolute(_dir.path_join(file))
	DirAccess.remove_absolute(_dir)


func test_status_lines_read_as_kilobytes() -> void:
	assert_int(ProcessStats.status_kb("VmRSS:\t  151612 kB", "VmRSS:")).is_equal(151612)
	assert_int(ProcessStats.status_kb("RssAnon:\t 78900 kB", "RssAnon:")).is_equal(78900)
	assert_int(ProcessStats.status_kb("VmRSS:\t  151612 kB", "RssAnon:")).is_equal(-1)
	assert_int(ProcessStats.status_kb("", "VmRSS:")).is_equal(-1)
	assert_int(ProcessStats.status_kb("VmRSS:\tlots kB", "VmRSS:")).is_equal(-1)


func test_cpu_ticks_are_user_and_system_after_the_name() -> void:
	assert_int(ProcessStats.cpu_ticks(STAT)).is_equal(300)
	assert_int(ProcessStats.cpu_ticks("7 (godot) S 1 2")).is_equal(-1)
	assert_int(ProcessStats.cpu_ticks("")).is_equal(-1)


func test_a_sample_gives_memory_then_the_share_of_a_core() -> void:
	var stats := ProcessStats.new()
	stats.status_path = _write("status", STATUS)
	stats.stat_path = _write("stat", STAT)
	var first := stats.sample(1_000_000)
	assert_float(first["rss_mb"]).is_equal_approx(148.1, 0.01)
	assert_float(first["anon_mb"]).is_equal_approx(77.1, 0.01)
	assert_bool(first.has("cpu_pct")).is_false()
	# 50 more ticks (0.5 s of processor at 100 a second) over 10 s of wall clock: 5% of a core.
	stats.stat_path = _write("stat", STAT.replace(" 250 50 ", " 280 70 "))
	assert_float(stats.sample(11_000_000)["cpu_pct"]).is_equal_approx(5.0, 0.01)


func test_no_procfs_gives_an_empty_sample() -> void:
	var stats := ProcessStats.new()
	stats.status_path = _dir.path_join("missing_status")
	stats.stat_path = _dir.path_join("missing_stat")
	assert_dict(stats.sample()).is_empty()


func _write(file_name: String, text: String) -> String:
	var path := _dir.path_join(file_name)
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(text)
	file.close()
	return path
