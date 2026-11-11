class_name StepTraceProbe
extends Node
## Is the character's step the same number on every platform? A game opened with `?steptrace` (a
## page) or `-- --steptrace` (the desktop) puts a body (`character.tscn`, the body a server
## steps) at `START` in the map and steps it `STEPS` times with commands that depend on the step's
## number alone (a slow turn, a sprint every other `LEG` steps, a jump every `JUMP_EVERY`), each
## `Character.step(command, 1 / 60)`, then publishes the body's position every `EVERY` steps
## with nine decimals: on the web to `window.gdtrace` (`done`, `trace`), on the desktop as one line
## starting `STEP_TRACE`, after which the game quits. Two traces of different platforms (the web
## build's wasm, Windows, Linux) that differ say the client's prediction and the server's step part
## ways by that much with no network at all (`tools/web_smoke/step_trace.py` reads both). It does
## nothing without the flag; the player rig adds it at run time, so no scene ships it.

## Where the body starts (the map's open floor beside the player's spawn) and how long it walks.
const START := Vector3(0.0, 1.0, 4.0)
const STEPS := 1800
const EVERY := 30
const LEG := 240
const JUMP_EVERY := 97
## Radians the view turns a step.
const TURN := 0.012
const BODY := "res://gameplay/character/character.tscn"

var _body: Character
var _step := 0
var _trace: Array[String] = []
var _command := PlayerCommand.new()


## True on a page opened with `?steptrace` or a desktop game started with `--steptrace`.
static func asked() -> bool:
	if OS.has_feature("web"):
		return bool(
			JavaScriptBridge.eval("new URLSearchParams(window.location.search).has('steptrace')")
		)
	return "--steptrace" in OS.get_cmdline_user_args()


## Adds a probe under `parent` (beside the map) when it was asked for (null otherwise).
static func attach(parent: Node) -> StepTraceProbe:
	if not asked():
		return null
	var probe := StepTraceProbe.new()
	probe.name = &"StepTraceProbe"
	parent.add_child(probe)
	return probe


## The command of step `index`: a function of the number alone.
static func command_at(index: int, into: PlayerCommand) -> PlayerCommand:
	into.clear()
	into.seq = index + 1
	into.yaw = wrapf(index * TURN, -PI, PI)
	into.move = Vector2(0.0, 1.0)
	into.sprint = floori(float(index) / LEG) % 2 == 1
	into.jump = index % JUMP_EVERY < 6
	into.jump_pressed = index % JUMP_EVERY == 0
	return into


func _ready() -> void:
	if OS.has_feature("web"):
		var out: JavaScriptObject = JavaScriptBridge.create_object("Object")
		out.done = false
		out.trace = "[]"
		JavaScriptBridge.get_interface("window").gdtrace = out
	_body = (load(BODY) as PackedScene).instantiate() as Character
	_body.name = &"TracedBody"
	_body.ragdoll_by_command = false
	add_child(_body)
	_body.set_physics_process(false)
	_body.teleport(START, 0.0)


func _physics_process(delta: float) -> void:
	if _step >= STEPS or _body == null:
		return
	_body.step(command_at(_step, _command), delta)
	_step += 1
	if _step % EVERY == 0:
		var at := _body.global_position
		_trace.append("%.9f,%.9f,%.9f" % [at.x, at.y, at.z])
	if _step == STEPS:
		_publish()


func _publish() -> void:
	var line := JSON.stringify({"steps": STEPS, "every": EVERY, "trace": _trace})
	if OS.has_feature("web"):
		var out: JavaScriptObject = JavaScriptBridge.get_interface("window").gdtrace
		out.trace = line
		out.done = true
	else:
		print("STEP_TRACE " + line)
		get_tree().quit()
