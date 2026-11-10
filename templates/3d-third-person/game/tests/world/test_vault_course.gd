# The vault course on the map: walls of several heights that carry a `Vaultable` (vaulted from the
# jump key, the tallest mantled) and one of a vaulting height without it, which is only jumped. The
# real player runs at each one in the level itself.
extends GdUnitTestSuite

const LEVEL := "res://world/prototype/prototype_level.tscn"
## The walls the player crosses, with what it does there.
const CROSSED := {
	"VaultCourse/Vault05": Character.State.VAULT,
	"VaultCourse/Vault09": Character.State.VAULT,
	"VaultCourse/Vault12": Character.State.VAULT,
	"VaultCourse/Mantle16": Character.State.MANTLE,
}

var _level: Node3D
var _player: Player
var _settings: VaultSettings
var _states: Array[Character.State] = []


func before_test() -> void:
	InputSim.release_all()
	_level = auto_free(load(LEVEL).instantiate())
	add_child(_level)
	_player = load("res://gameplay/player/player.tscn").instantiate() as Player
	_player.start_at_spawn = false
	_level.add_child(_player)
	_settings = _player.vault_settings
	_states = []
	_player.state_changed.connect(func(state: Character.State) -> void: _states.append(state))
	await InputSim.ticks(get_tree(), 4)


func after_test() -> void:
	InputSim.release_all()


func _block(path: String) -> ProtoBlock:
	return _level.get_node(path) as ProtoBlock


# Runs east (the right key, with no camera) at `block` from 1.3 m before its west face (clear of
# the wall before it) and presses jump 0.6 m before it; returns where the feet end.
func _run_at(block: ProtoBlock) -> Vector3:
	var west := block.global_position.x - block.size.x / 2.0
	_player.teleport(Vector3(west - 1.3, 0.0, block.global_position.z), PI / 2.0)
	_states = []
	await InputSim.ticks(get_tree(), 4)
	InputSim.key(KEY_D, true)
	for _tick in 120:
		await get_tree().physics_frame
		if _player.global_position.x >= west - _player.tuning.radius - 0.6:
			break
	InputSim.key(KEY_SPACE, true)
	await InputSim.ticks(get_tree(), 4)
	InputSim.key(KEY_SPACE, false)
	await InputSim.ticks(get_tree(), 50)
	InputSim.key(KEY_D, false)
	await InputSim.ticks(get_tree(), 20)
	return _player.global_position


func test_each_course_wall_is_sized_for_what_it_teaches() -> void:
	for path: String in CROSSED:
		var block := _block(path)
		var marker: Vaultable = null
		for child in block.get_children():
			if child is Vaultable:
				marker = child
		assert_object(marker).override_failure_message(path).is_not_null()
		if CROSSED[path] == Character.State.VAULT:
			assert_float(block.size.y).is_between(
				_settings.min_vault_height, _settings.max_vault_height
			)
			assert_float(block.size.x).is_less_equal(_settings.max_vault_depth)
		else:
			assert_float(block.size.y).is_between(
				_settings.max_vault_height, _settings.max_mantle_height
			)
	var plain := _block("VaultCourse/NoVault09")
	for child in plain.get_children():
		assert_bool(child is Vaultable).is_false()
	assert_float(plain.size.y).is_between(_settings.min_vault_height, _settings.max_vault_height)


func test_the_player_vaults_each_low_wall_and_mantles_the_high_one() -> void:
	for path: String in CROSSED:
		var block := _block(path)
		var end := await _run_at(block)
		var east := block.global_position.x + block.size.x / 2.0
		assert_bool(_states.has(CROSSED[path])).override_failure_message(path).is_true()
		if CROSSED[path] == Character.State.VAULT:
			assert_float(end.x).override_failure_message(path).is_greater(east)
			assert_float(end.y).override_failure_message(path).is_equal_approx(0.0, 0.02)
		else:
			assert_float(end.y).override_failure_message(path).is_equal_approx(block.size.y, 0.03)


func test_the_wall_without_the_component_is_jumped_not_vaulted() -> void:
	await _run_at(_block("VaultCourse/NoVault09"))
	assert_bool(_states.has(Character.State.VAULT)).is_false()
	assert_bool(_states.has(Character.State.JUMP)).is_true()
	assert_str(_player.vault_motion().last_refusal).is_equal(VaultPlan.NOT_VAULTABLE)
