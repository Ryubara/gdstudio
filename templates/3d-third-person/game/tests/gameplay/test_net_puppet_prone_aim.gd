# The prone aim's start and end on another screen (kit #1356): Ada lies down and aims, then lets
# the aim go, in a game served over a loopback link, and on every drawn update of Bo's puppet of
# her while its prone aim blends (`ProneAimWatch`) neither hand goes under the floor, neither arm
# folds back under the chest and the pistol never shows under the floor.
extends GdUnitTestSuite

## Where Ada lies, clear of the prototype level's parts (the puppet aim tour's lane).
const SPOT := Vector3(5.0, 0.0, 16.6)


func test_a_puppet_s_arms_stay_over_the_floor_as_its_prone_aim_starts_and_ends() -> void:
	var rig: OnlineRig = auto_free(OnlineRig.new(true))
	add_child(rig)
	assert_bool(rig.start()).is_true()
	var ada := await rig.join("Ada")
	var bo := await rig.join("Bo")
	assert_object(ada).is_not_null()
	assert_object(bo).is_not_null()
	await rig.wait(20)
	rig.server_body(ada).teleport(SPOT, PI)
	ada.player.teleport(SPOT, PI)
	var controller := rig.controllers[rig.clients.find(ada)]
	var lie := PlayerCommand.new()
	lie.prone = true
	controller.next = lie
	await rig.wait(90)
	var puppet := bo.remote_players.puppet_at(ada.slot)
	assert_object(puppet).is_not_null()
	assert_bool(puppet.prone).override_failure_message("the puppet does not lie").is_true()
	var watch := ProneAimWatch.new(puppet)
	watch.start()
	var aimed := PlayerCommand.new()
	aimed.prone = true
	aimed.aim = true
	controller.next = aimed
	for _frame in 40:
		await get_tree().process_frame
	controller.next = lie
	for _frame in 40:
		await get_tree().process_frame
	watch.stop()
	var fails := watch.failures("puppet")
	assert_array(fails).override_failure_message("\n".join(fails)).is_empty()
