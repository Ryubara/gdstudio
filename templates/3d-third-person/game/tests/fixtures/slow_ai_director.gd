# On the clock: it makes the director's step cost `factor` times its own wall-clock time.
class_name SlowAiDirector
extends AiDirector
## A director whose step costs `factor` times what its work took (it spins on the clock as long
## again after the step), on any machine: the AI cost gate's mutation, a step made slower to prove
## the gate fails on it (kit docs/engines/godot/third-person/ai-characters.md#cost-gate). What the
## characters do is unchanged.

## How many times its own work the step costs.
var factor := 2.0


func _physics_process(delta: float) -> void:
	var start := Time.get_ticks_usec()
	super(delta)
	var until := start + int((Time.get_ticks_usec() - start) * factor)
	while Time.get_ticks_usec() < until:
		pass
	last_step_usec = Time.get_ticks_usec() - start
