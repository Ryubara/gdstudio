# The camera zone's and the interactor's inspector contract: defaults pinned, each setting changed
# on a running node and its effect read.
extends GdUnitTestSuite

var _zone: TriggerZone
var _camera: PhantomCamera3D
var _link: CameraZone


func before_test() -> void:
	_zone = load("res://gameplay/trigger_zone/trigger_zone.tscn").instantiate() as TriggerZone
	_camera = PhantomCamera3D.new()
	_link = CameraZone.new()
	_link.zone = _zone
	_link.camera = _camera
	add_child(_zone)
	add_child(_camera)
	add_child(_link)


func after_test() -> void:
	_link.free()
	_camera.free()
	_zone.free()


func test_every_export_has_its_default_pinned() -> void:
	var fresh := CameraZone.new()
	var pins := {
		&"zone": null,
		&"camera": null,
		&"priority_inside": 20,
		&"priority_outside": 0,
	}
	assert_array(ExportPins.differences(fresh, pins)).is_empty()
	assert_array(ExportPins.wrong_values(fresh, pins)).is_empty()
	fresh.free()


func test_it_says_what_it_needs_through_a_warning() -> void:
	var bare := CameraZone.new()
	assert_array(bare._get_configuration_warnings()).has_size(2)
	assert_array(_link._get_configuration_warnings()).is_empty()
	bare.free()


func test_the_two_priorities_are_read_when_the_view_changes() -> void:
	_link.priority_inside = 55
	_link.priority_outside = 3
	assert_int(_camera.priority).is_equal(3)
	var body := Node3D.new()
	_zone._on_body_entered(body)
	assert_int(_camera.priority).is_equal(55)
	_link.priority_inside = 60
	_zone._on_body_exited(body)
	assert_int(_camera.priority).is_equal(3)
	_zone._on_body_entered(body)
	assert_int(_camera.priority).is_equal(60)
	body.free()


func test_the_interactors_half_angle_sets_what_counts_as_in_front() -> void:
	var interactor := Interactor.new()
	add_child(interactor)
	var door := load("res://gameplay/door/door.tscn").instantiate() as Door
	door.position = Vector3(1.0, 0.0, 0.0)
	add_child(door)
	assert_float(interactor.half_angle).is_equal(75.0)
	assert_object(interactor.find_target(Vector3.FORWARD, 2.0)).is_null()
	interactor.half_angle = 120.0
	assert_object(interactor.find_target(Vector3.FORWARD, 2.0)).is_same(door)
	door.free()
	interactor.free()
