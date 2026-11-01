class_name CrowdLod
extends Node
## Animation throttle. Zombies far from the camera, or outside its view, advance their AnimationTree
## every Nth frame (with the time they missed), the tree running in manual callback mode.

const NEAR := 14.0
const MID := 24.0
const PERIOD_NEAR := 1
const PERIOD_MID := 3
const PERIOD_FAR := 6
const PERIOD_OFFSCREEN := 12
const RETIER_EVERY := 8

var zombies: Array[Zombie] = []
var camera: Camera3D
var _periods: Array[int] = []
var _frame := 0


func add_zombie(z: Zombie) -> void:
	zombies.append(z)
	_periods.append(PERIOD_NEAR)
	z.tree.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL


func _process(delta: float) -> void:
	_frame += 1
	for i in zombies.size():
		var z := zombies[i]
		if (_frame + i) % RETIER_EVERY == 0:
			_periods[i] = _period_for(z)
		z.accumulated += delta
		if (_frame + i) % _periods[i] == 0:
			z.tree.advance(z.accumulated)
			z.accumulated = 0.0


func _period_for(z: Zombie) -> int:
	var p := z.global_position + Vector3(0.0, 1.0, 0.0)
	if not camera.is_position_in_frustum(p):
		return PERIOD_OFFSCREEN
	var d := camera.global_position.distance_to(p)
	if d < NEAR:
		return PERIOD_NEAR
	return PERIOD_MID if d < MID else PERIOD_FAR
