extends Node
## Where an AI character's body step goes (gdstudio #1059): 40 walking `ai_character.tscn` stepped
## by this node, in blocks of ticks that alternate between the real step (the controller's
## `sample()` then `Character.step()`, the way the `AiDirector` steps a body) and a copy of the
## step cut into its modules, each module run for every body before the next one starts, so a
## module's time is read over the whole crowd at once (a browser's clock is 5 µs at best).
##
## The copy follows `Character.step()` and `_move()` part for part on the path a body that walks
## takes (no vault, no slide): keep it in step with them when they change, or its sum drifts from
## the real step, which it prints beside it (`real_us` against `sum_us`).
##
## One line of JSON, `AI_STEP_PROFILE {...}`: microseconds a body a tick for the real step and for
## each module (`modules`, in the step's order), the empty loop over the crowd (`loop_us`, what one
## module's timing costs on its own), and a fixed loop of GDScript timed first (`calibration_ms`),
## as `ai_cost_bench.gd` reads it. Desktop: `godot --headless --fixed-fps 60 --path game
## res://tools/bench/ai_step_profile.tscn [-- --count=40 --lean=on|off]`; browser: a web export
## with this scene as `run/main_scene`, read by `tools/bench/ai_step_profile.py`
## (`window.__ai_step_profile`, the same options in the page's query).

const CHARACTER := "res://gameplay/ai/ai_character.tscn"
const SPACING := 3.0
const WALK_STRENGTH := 0.35
const TURN_EVERY := 30
const WARM_TICKS := 60
const BLOCK_TICKS := 100
const BLOCKS := 3
const CALIBRATION_ROUNDS := 200000
const MODULES: Array[String] = [
	"sample",
	"command",
	"timers_prone",
	"vault",
	"slide",
	"crouch",
	"aim",
	"steer",
	"vertical",
	"climb",
	"move_and_slide",
	"push",
	"after_move",
	"use_input",
	"weapon_tick",
]

var _characters: Array[AiCharacter] = []
var _commands: Array[PlayerCommand] = []
var _before: PackedVector3Array = PackedVector3Array()
var _wishes: PackedVector3Array = PackedVector3Array()
var _lowered := PackedFloat32Array()
var _live: PackedByteArray = PackedByteArray()
var _sums := PackedFloat64Array()
var _loop_sum := 0.0
var _present_sum := 0.0
var _real_sum := 0.0
var _real_ticks := 0
var _profiled_ticks := 0
var _tick := 0
var _count := 40
var _lean := ""
var _rng := RandomNumberGenerator.new()
var _done := false


func _ready() -> void:
	_rng.seed = 1059
	_read_options()
	_sums.resize(MODULES.size())
	var floor_body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(400.0, 1.0, 400.0)
	shape.shape = box
	floor_body.add_child(shape)
	floor_body.position = Vector3(0.0, -0.5, 0.0)
	add_child(floor_body)
	var camera := Camera3D.new()
	camera.position = Vector3(0.0, 30.0, 40.0)
	camera.rotation.x = deg_to_rad(-35.0)
	add_child(camera)
	camera.make_current()
	var scene := load(CHARACTER) as PackedScene
	var side := ceili(sqrt(_count))
	for index in _count:
		var character := scene.instantiate() as AiCharacter
		var cell := (
			Vector2(index % side, floorf(float(index) / side)) - Vector2.ONE * (side - 1) / 2.0
		)
		character.position = Vector3(cell.x * SPACING, 0.0, cell.y * SPACING + 2.0)
		add_child(character)
		character.set_physics_process(false)
		if _lean != "":
			character.controller.lean_step = _lean == "on"
		var angle := _rng.randf() * TAU
		character.ai_controller().walk_direction = Vector3(cos(angle), 0.0, sin(angle))
		character.ai_controller().walk_strength = WALK_STRENGTH
		_characters.append(character)
		_commands.append(null)
	_before.resize(_count)
	_wishes.resize(_count)
	_lowered.resize(_count)
	_live.resize(_count)


func _physics_process(delta: float) -> void:
	if _done:
		return
	_tick += 1
	if _tick % TURN_EVERY == 0:
		_turn_a_little()
	if _tick <= WARM_TICKS:
		_real(delta)
		return
	var block := (_tick - WARM_TICKS - 1) / BLOCK_TICKS
	if block >= BLOCKS * 2:
		_finish()
		return
	if block % 2 == 0:
		var start := Time.get_ticks_usec()
		_real(delta)
		_real_sum += Time.get_ticks_usec() - start
		_real_ticks += 1
	else:
		_profiled(delta)
		_profiled_ticks += 1


func _real(delta: float) -> void:
	for character in _characters:
		character.step(character.controller.sample(), delta)


# The step cut into its modules, each run over the crowd before the next (see the top).
func _profiled(delta: float) -> void:
	var count := _characters.size()
	var t := Time.get_ticks_usec()
	for index in count:
		pass
	t = _lap_loop(t)
	for index in count:
		_commands[index] = _characters[index].controller.sample()
	t = _lap(0, t)
	for index in count:
		var c := _characters[index]
		var command := _commands[index]
		if command.all_finite():
			c.last_command.copy_from(command)
			c.last_command.move = command.move.limit_length(1.0)
		else:
			c.last_command.clear()
		c.view_yaw = c.last_command.yaw
		c.view_pitch = c._prone.held_pitch(c.prone_tuning, c.last_command.pitch)
		if c.ragdoll_by_command and c.last_command.ragdoll_pressed:
			c.ragdoll = not c.ragdoll
		_live[index] = (
			1
			if c.state != Character.State.DEAD and c.global_position.y >= c.tuning.fall_limit
			else 0
		)
	t = _lap(1, t)
	for index in count:
		if _live[index]:
			_characters[index]._tick_timers(delta)
			_characters[index]._update_prone(delta)
	t = _lap(2, t)
	for index in count:
		if _live[index] and _characters[index].vault_motion.drive(_characters[index], delta):
			_live[index] = 0
	t = _lap(3, t)
	for index in count:
		var c := _characters[index]
		if _live[index]:
			_lowered[index] = c._slide.amount
			c._slide.begin_tick(c, c._wants_crouch, c._coyote, c._action_lock > 0.0, delta)
	t = _lap(4, t)
	for index in count:
		if _live[index]:
			_characters[index]._update_crouch(delta)
	t = _lap(5, t)
	for index in count:
		var c := _characters[index]
		if _live[index]:
			c._update_aim(delta)
			if c._slide.amount != _lowered[index]:
				c._fit_body()
	t = _lap(6, t)
	for index in count:
		var c := _characters[index]
		if not _live[index]:
			continue
		var wish := c._wish_direction() if c._action_lock <= 0.0 else Vector3.ZERO
		_wishes[index] = wish
		if c._slide.active:
			c._slide.steer(c, wish, delta)
			c._present_facing()
		else:
			c._steer(wish, delta)
	t = _lap(7, t)
	for index in count:
		if _live[index]:
			_characters[index]._vertical(delta)
	t = _lap(8, t)
	for index in count:
		if _live[index]:
			_characters[index]._climb(delta)
	t = _lap(9, t)
	for index in count:
		var c := _characters[index]
		if not _live[index]:
			continue
		_before[index] = c.velocity
		var ticks := roundf(delta / get_physics_process_delta_time())
		c.velocity *= ticks
		c.move_and_slide()
		c.velocity /= ticks
		c._grounded = c.is_on_floor()
	t = _lap(10, t)
	for index in count:
		if _live[index]:
			var c := _characters[index]
			c._pushing = CharacterPush.push_props(c, _before[index], delta)
	t = _lap(11, t)
	for index in count:
		if _live[index]:
			_characters[index]._after_move(_wishes[index], delta)
	t = _lap(12, t)
	for index in count:
		if _live[index]:
			_characters[index]._use_input(delta)
	t = _lap(13, t)
	for index in count:
		var c := _characters[index]
		if c.loadout != null:
			c.loadout.tick(delta)
		if c.weapon != null:
			c.weapon.tick(delta)
	t = _lap(14, t)
	# Apart, not part of the sum: what showing the facing on the model costs (in `steer`).
	for index in count:
		_characters[index]._present_facing()
	_present_sum += Time.get_ticks_usec() - t


func _lap(module: int, since: int) -> int:
	var now := Time.get_ticks_usec()
	_sums[module] += now - since
	return now


func _lap_loop(since: int) -> int:
	var now := Time.get_ticks_usec()
	_loop_sum += now - since
	return now


func _finish() -> void:
	_done = true
	var per := float(_count * _profiled_ticks)
	var modules := {}
	var total := 0.0
	for index in MODULES.size():
		var each := _sums[index] / per
		modules[MODULES[index]] = snappedf(each, 0.01)
		total += each
	var report := {
		"count": _count,
		"web": OS.has_feature("web"),
		"debug": OS.is_debug_build(),
		"lean": _lean,
		"calibration_ms": _calibrate(),
		"real_us": snappedf(_real_sum / float(_count * _real_ticks), 0.01),
		"sum_us": snappedf(total, 0.01),
		"loop_us": snappedf(_loop_sum / per, 0.01),
		"present_facing_us": snappedf(_present_sum / per, 0.01),
		"modules": modules,
	}
	var line := JSON.stringify(report)
	print("AI_STEP_PROFILE ", line)
	if OS.has_feature("web"):
		JavaScriptBridge.eval("window.__ai_step_profile = %s;" % line, true)
	else:
		get_tree().quit()


# Each walker turns up to 40 degrees, and back toward the middle once it is far out.
func _turn_a_little() -> void:
	for character in _characters:
		var controller := character.ai_controller()
		var way := controller.walk_direction.rotated(Vector3.UP, _rng.randf_range(-0.7, 0.7))
		if character.global_position.length() > 25.0:
			way = -character.global_position.normalized()
			way.y = 0.0
		controller.walk_direction = way


# `count=40` and `lean=on|off`, from the command line after `--` or the page's query.
func _read_options() -> void:
	var words := PackedStringArray()
	if OS.has_feature("web"):
		var query := str(JavaScriptBridge.eval("window.location.search", true))
		words = query.trim_prefix("?").split("&", false)
	else:
		for word in OS.get_cmdline_user_args():
			words.append(word.trim_prefix("--"))
	for word in words:
		var parts := word.split("=")
		if parts.size() != 2:
			continue
		if parts[0] == "count":
			_count = maxi(int(parts[1]), 1)
		elif parts[0] == "lean":
			_lean = parts[1]


# Milliseconds a fixed loop of GDScript takes: the machine's speed now.
func _calibrate() -> float:
	var start := Time.get_ticks_usec()
	var value := 0.0
	for index in CALIBRATION_ROUNDS:
		value = sin(value + index) * 0.5
	return (Time.get_ticks_usec() - start + int(value * 0.0)) / 1000.0
