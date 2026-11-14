class_name CountingAi
extends AiCharacter
## A guard that counts its own processing, for a test that a client of a server runs no AI
## (gdstudio #970): the counts are shared by every one (`AiCallCounts`), so a test reads them
## before and after. No static variable here: see `AiCallCounts`.


func _process(_delta: float) -> void:
	AiCallCounts.process += 1


func _physics_process(delta: float) -> void:
	AiCallCounts.physics += 1
	super(delta)


func think(seconds: float) -> void:
	AiCallCounts.thinks += 1
	super(seconds)


## The counts so far: `physics`, `process` and `thinks`.
static func new_counts() -> Dictionary:
	return {
		"physics": AiCallCounts.physics,
		"process": AiCallCounts.process,
		"thinks": AiCallCounts.thinks,
	}
