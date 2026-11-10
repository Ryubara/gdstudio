# Aiming and shooting lying down, through simulated input: the crawl slows while aiming (and more
# backwards), the shot leaves with the prone share of the spread, and the tuning can forbid aiming
# and firing on the ground. The rest of prone is in test_prone.gd.
extends GdUnitTestSuite

var _arena: PlayArena
var _player: Player
var _prone: ProneTuning
var _tuning: CharacterTuning


func before_test() -> void:
	InputSim.release_all()
	_arena = auto_free(PlayArena.new())
	add_child(_arena)
	_player = _arena.add_player(Vector3.ZERO)
	_player.tuning = (
		(load("res://gameplay/player/player_tuning.tres") as CharacterTuning).duplicate()
	)
	_player.prone_tuning = (
		(load("res://gameplay/player/prone_tuning.tres") as ProneTuning).duplicate()
	)
	_tuning = _player.tuning
	_prone = _player.prone_tuning
	await InputSim.ticks(get_tree(), 4)


func after_test() -> void:
	InputSim.release_all()
	AudioDrain.stop_all(_arena)


func _ticks(seconds: float) -> int:
	return ceili(seconds * Engine.physics_ticks_per_second) + 2


func _tap(code: Key) -> void:
	InputSim.key(code, true)
	await InputSim.ticks(get_tree(), 2)
	InputSim.key(code, false)
	await InputSim.ticks(get_tree(), 1)


func _lie_down() -> void:
	await _tap(KEY_Z)
	await InputSim.ticks(get_tree(), _ticks(_prone.enter_time))


func test_crawling_backwards_while_aiming_is_slower_still() -> void:
	await _lie_down()
	InputSim.mouse_button(MOUSE_BUTTON_RIGHT, true)
	InputSim.key(KEY_S, true)
	await InputSim.ticks(get_tree(), 60)
	assert_bool(_player.aiming).is_true()
	var expected := _prone.crawl_speed * _prone.backward_share * _prone.aim_move_share
	assert_float(_player.ground_speed()).is_equal_approx(expected, 0.03)


func test_it_aims_and_shoots_lying_down_with_less_spread() -> void:
	await _lie_down()
	_player.weapon.definition = _player.weapon.definition.duplicate()
	_player.weapon.definition.spread = 4.0
	InputSim.mouse_button(MOUSE_BUTTON_RIGHT, true)
	await InputSim.ticks(get_tree(), 20)
	assert_bool(_player.aiming).is_true()
	var shots: Array[Projectile] = []
	_player.weapon.fired.connect(func(shot: Projectile) -> void: shots.append(shot))
	InputSim.mouse_button(MOUSE_BUTTON_LEFT, true)
	await InputSim.ticks(get_tree(), 4)
	InputSim.mouse_button(MOUSE_BUTTON_LEFT, false)
	await InputSim.ticks(get_tree(), 4)
	assert_int(shots.size()).is_equal(1)
	assert_float(_player.weapon.spread_share).is_equal(_prone.spread_share)


func test_the_tuning_can_forbid_aiming_and_firing_lying_down() -> void:
	_prone.aim_allowed = false
	await _lie_down()
	InputSim.mouse_button(MOUSE_BUTTON_RIGHT, true)
	InputSim.mouse_button(MOUSE_BUTTON_LEFT, true)
	await InputSim.ticks(get_tree(), 20)
	assert_bool(_player.aiming).is_false()
	InputSim.release_all()
	_prone.aim_allowed = true
	_prone.fire_allowed = false
	var shots: Array[Projectile] = []
	_player.weapon.fired.connect(func(shot: Projectile) -> void: shots.append(shot))
	InputSim.mouse_button(MOUSE_BUTTON_RIGHT, true)
	await InputSim.ticks(get_tree(), 20)
	InputSim.mouse_button(MOUSE_BUTTON_LEFT, true)
	await InputSim.ticks(get_tree(), 20)
	assert_bool(_player.aiming).is_true()
	assert_bool(_player.fire_held).is_false()
	assert_array(shots).is_empty()
