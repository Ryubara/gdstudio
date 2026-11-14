# A suite that names `CharacterController` before `PlayerInput` exits with nothing in use: a
# subclass of a game class that keeps a static variable of its own left GdUnit4's scripts and the
# autoloads' in use at exit under Godot 4.7.2 (213 objects, 118 resources), so `PlayerInput`'s
# shared key holders live in `RagdollKeyHolders` (gdstudio #1500; the kit's
# `docs/engines/godot/test-exit-leaks.md#a-subclass-with-statics`). Its proof is this suite run
# alone (`gds template test 3d-third-person --suite tests/gameplay/test_player_input_exit.gd`)
# with no `leaked at exit` or `still in use` line in the log.
extends GdUnitTestSuite


func test_the_suite_names_the_controller_then_the_player_input() -> void:
	assert_bool(true).is_true()


# Never called: the suite only names the two classes, base first, as the leaking suites did.
func _names() -> void:
	print(CharacterController)
	print(PlayerInput)
