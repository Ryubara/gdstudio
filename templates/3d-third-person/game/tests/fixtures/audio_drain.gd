class_name AudioDrain
extends RefCounted
## For a suite that makes a sound play: stops every audio player under a node and waits until the
## audio thread has let go of the voices, so the process can quit with nothing leaked (a voice
## that is still playing at exit is reported as `ObjectDB instances were leaked`).


static func stop_all(root: Node) -> void:
	AudioSettings.stop_players(root)
	AudioSettings.drain_mixer()
