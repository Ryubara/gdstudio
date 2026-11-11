@tool
class_name AiSay
extends AiStockTask
## Says a bark (`line`) through the brain, which lets it through only past its cooldowns (this
## line, any line, anybody's same line) and emits `AiBrain.barked`; the character's own sound and
## subtitles play it, and nothing of it is sent over the network. It ends at once either way.

## The line's id (what the character's voice and subtitles look up).
@export var line := &""


func _init() -> void:
	id = &"say"
	layer = Layer.RESPONSE
	channels = Channel.SPEAK


func update(_delta: float) -> Status:
	var mind := brain()
	if mind != null and line != &"":
		mind.say(line)
	return Status.SUCCEEDED


func has_end_condition() -> bool:
	return true
