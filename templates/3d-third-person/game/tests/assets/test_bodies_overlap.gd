extends GdUnitTestSuite
## The limb overlap reports name what made their numbers (kit #1479): the hash of the measure
## script's code and of each body file. `BodiesOverlap.stale` fails a report whose script or body
## is no longer the one measured, and the hash of the code is the same in GDScript here as in
## Python where the reports are written (`assets/animation/measure_hash.py`).

const PRONE := "res://assets/animation/prone/prone_form_female.glb"
const BODY := "form_female"
const PLAIN := (
	"def depth(a, b):\n    for way in RAYS:\n        hit = cast(a, way)\n"
	+ '    return f"{a} in {b}"\n'
)
## Texts and the hash of their normal form: the same list as `CASES` in `measure_hash.py`, whose
## `--self-test` holds Python to these hashes.
const CASES: Dictionary[String, Array] = {
	"plain": [PLAIN, "59642f049fac6d004894f80f5e508c346cde0204f5a711c558fb805f39816282"],
	"comments, a docstring, blank lines and a wrapped call":
	[
		(
			'"""A module."""\n\n# a comment\ndef depth(a, b):  # how deep\n'
			+ '    """A docstring: with a # in it.\n\n    And a second line.\n    """\n'
			+ "    for way in RAYS:\n\n        hit = cast(\n            a,\n            way\n"
			+ '        )\n    return f"{a} in {b}"\r\n'
		),
		"59642f049fac6d004894f80f5e508c346cde0204f5a711c558fb805f39816282"
	],
	"a statement moved out of the loop":
	[
		(
			"def depth(a, b):\n    for way in RAYS:\n        pass\n    hit = cast(a, way)\n"
			+ '    return f"{a} in {b}"\n'
		),
		"7eb04ae1521637aa5c7485252915c10fb68e3d970d8652bd9a27ce4f2bbfa70e"
	],
	"a string with a space more":
	[
		(
			"def depth(a, b):\n    for way in RAYS:\n        hit = cast(a, way)\n"
			+ '    return f"{a}  in {b}"\n'
		),
		"ec0de1182c6f8931d5a0f9a7ee62c400d65bf4ef173f5608ec5f3d69ee5b84cb"
	],
}

var _copies: Array[String] = []


func after_test() -> void:
	for copy in _copies:
		DirAccess.remove_absolute(copy)
	_copies.clear()


# A copy of the measure script with `more` added at its end, outside the game.
func _changed(more: String) -> String:
	var copy := "user://limb_overlap_%d_%d.py" % [Time.get_ticks_usec(), _copies.size()]
	var file := FileAccess.open(copy, FileAccess.WRITE)
	file.store_string(FileAccess.get_file_as_string(BodiesOverlap.MEASURE) + more)
	file.close()
	_copies.append(copy)
	return copy


func test_the_code_hash_is_the_one_python_writes() -> void:
	for case: String in CASES:
		var found := BodiesOverlap.code_sha256(CASES[case][0])
		assert_str(found).override_failure_message("%s: %s" % [case, found]).is_equal(
			CASES[case][1]
		)


func test_a_report_of_the_game_s_script_and_bodies_is_not_stale() -> void:
	var found := BodiesOverlap.stale(BodiesOverlap.read(PRONE), [BODY])
	assert_array(found).override_failure_message("; ".join(found)).is_empty()


func test_a_comment_or_a_wrapped_line_in_the_script_keeps_a_report() -> void:
	var wrapped := _changed("\n\n# a note\nUNUSED = (\n    1,  # one\n    2\n)  \n")
	var plain := _changed("\nUNUSED = (1, 2)\n")
	assert_str(BodiesOverlap.code_sha256(FileAccess.get_file_as_string(wrapped))).is_equal(
		BodiesOverlap.code_sha256(FileAccess.get_file_as_string(plain))
	)
	var noted := _changed("\n\n# a note on the measure\n")
	var found := BodiesOverlap.stale(BodiesOverlap.read(PRONE), [BODY], noted)
	assert_array(found).override_failure_message("; ".join(found)).is_empty()


func test_a_change_to_the_script_s_code_fails_a_report() -> void:
	var changed := _changed("\nLIMIT_MM = 6.0\n")
	var found := BodiesOverlap.stale(BodiesOverlap.read(PRONE), [BODY], changed)
	assert_array(found).has_size(1)
	assert_str(found[0]).contains("is not the script that measured prone_form_female.glb")


func test_a_report_that_names_no_script_or_another_body_fails() -> void:
	var report := BodiesOverlap.read(PRONE).duplicate(true)
	report.erase("measure_sha256")
	assert_array(BodiesOverlap.stale(report, [BODY])).has_size(1)
	report = BodiesOverlap.read(PRONE).duplicate(true)
	# the report of the female's file was not made on the male's skin
	var found := BodiesOverlap.stale(report, ["form_male"])
	assert_array(found).has_size(1)
	assert_str(found[0]).contains("form_male.glb is not the body")
	report.bodies_sha256[BODY] = "0".repeat(64)
	found = BodiesOverlap.stale(report, [BODY])
	assert_array(found).has_size(1)
	assert_str(found[0]).contains("form_female.glb is not the body")
	assert_array(BodiesOverlap.stale(report, ["nobody"])).has_size(1)
