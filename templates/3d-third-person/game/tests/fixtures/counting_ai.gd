class_name CountingAi
extends AiCharacter
## A guard that counts its own processing, for a test that a client of a server runs no AI
## (gdstudio #970): the counts are shared by every one, so a test reads them before and after.

static var physics_calls := 0
static var process_calls := 0
static var thinks := 0


func _process(_delta: float) -> void:
	process_calls += 1


func _physics_process(delta: float) -> void:
	physics_calls += 1
	super(delta)


func think(seconds: float) -> void:
	thinks += 1
	super(seconds)


## The counts so far: `physics`, `process` and `thinks`.
static func new_counts() -> Dictionary:
	return {"physics": physics_calls, "process": process_calls, "thinks": thinks}
