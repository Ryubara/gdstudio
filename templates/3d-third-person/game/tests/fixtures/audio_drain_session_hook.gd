extends GdUnitTestSessionHook
## Lets go of every voice once the last suite has run, so no run ends with a sound in the mixer.
##
## The menus' sound service (`MenuSounds`, an autoload) outlives every suite, and a suite that opens
## a screen (`test_screen_host.gd`) leaves its swish or press playing. After the last suite GdUnit
## quits within a few frames, which on `--fixed-fps` pass in milliseconds, while the headless audio
## thread mixes every 70 to 90 ms: the voice was still held at exit (`10 ObjectDB instances were
## leaked`, two decoded menu sounds), whichever suite happened to run last (gdstudio #1506). Here
## every player in the tree is stopped and the mixer is waited on, then a frame lets the main thread
## delete what the audio thread let go of. Registered in `project.godot` (`gdunit4/hooks`).

## The frames after the drain in which the main thread deletes the released playbacks.
const RELEASE_FRAMES := 2


func _init() -> void:
	super("Audio drain", "Stops every voice and waits on the mixer before the run quits.")


func startup(_session: GdUnitTestSession) -> GdUnitResult:
	return GdUnitResult.success()


func shutdown(_session: GdUnitTestSession) -> GdUnitResult:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return GdUnitResult.success()
	AudioDrain.stop_all(tree.root)
	for _frame in RELEASE_FRAMES:
		await tree.process_frame
	return GdUnitResult.success()
