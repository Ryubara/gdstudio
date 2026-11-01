class_name Zombie
extends CharacterBody3D
## One chasing zombie: model + AnimationTree (walk/run blend, punch one-shot) + NavigationAgent3D with avoidance.

const ATTACK_RANGE := 1.5
const STOP_RANGE := 1.1
const WALK_SPEED := 2.0
const RUN_SPEED := 4.0
const GRAVITY := 9.8
const TURN_RATE := 10.0

var speed := 3.0
var accumulated := 0.0  ## animation time not yet advanced (used by the throttle)
var agent: NavigationAgent3D
var tree: AnimationTree
var body_mesh: MeshInstance3D
var eyelid_mesh: MeshInstance3D
var repath_interval := 0.0  ## 0 = every physics tick
var avoidance := true

var _target: Node3D
var _repath_clock := 0.0
var _attack_clock := 0.0


func setup(model_scene: PackedScene, target: Node3D, opts: Dictionary) -> void:
	_target = target
	speed = opts["speed"]
	repath_interval = opts["repath_interval"]
	avoidance = opts["avoidance"]
	_repath_clock = opts["repath_phase"]
	_attack_clock = opts["attack_phase"]
	collision_layer = 2
	collision_mask = 1  # floor only: zombies avoid each other with RVO, not with physics

	var cap := CollisionShape3D.new()
	var shape := CapsuleShape3D.new()
	shape.radius = 0.4
	shape.height = 1.8
	cap.shape = shape
	cap.position.y = 0.9
	add_child(cap)

	agent = NavigationAgent3D.new()
	agent.radius = 0.4
	agent.height = 1.8
	agent.max_speed = RUN_SPEED
	agent.path_desired_distance = 0.6
	agent.target_desired_distance = STOP_RANGE
	agent.avoidance_enabled = avoidance
	if opts["avoid_tune"]:
		agent.neighbor_distance = 3.0
		agent.max_neighbors = 5
	if avoidance:
		agent.velocity_computed.connect(_on_safe_velocity)
	add_child(agent)

	var model: Node3D = model_scene.instantiate()
	add_child(model)
	body_mesh = model.find_child("Zombie", true, false)
	eyelid_mesh = model.find_child("Eyelid", true, false)
	if opts["no_eyelid"]:
		eyelid_mesh.queue_free()
		eyelid_mesh = null
	if opts["vis_range"] > 0.0:
		for m in [body_mesh, eyelid_mesh]:
			if m:
				m.visibility_range_end = opts["vis_range"]
	_build_tree(model)


func _build_tree(model: Node3D) -> void:
	var bt := AnimationNodeBlendTree.new()
	var walk := AnimationNodeAnimation.new()
	walk.animation = &"Walk"
	var run := AnimationNodeAnimation.new()
	run.animation = &"Run"
	var punch := AnimationNodeAnimation.new()
	punch.animation = &"Punch"
	bt.add_node(&"walk", walk)
	bt.add_node(&"run", run)
	bt.add_node(&"punch", punch)
	bt.add_node(&"gait", AnimationNodeBlend2.new())
	bt.add_node(&"shot", AnimationNodeOneShot.new())
	bt.connect_node(&"gait", 0, &"walk")
	bt.connect_node(&"gait", 1, &"run")
	bt.connect_node(&"shot", 0, &"gait")
	bt.connect_node(&"shot", 1, &"punch")
	bt.connect_node(&"output", 0, &"shot")

	tree = AnimationTree.new()
	tree.tree_root = bt
	model.add_child(tree)  # sibling of the AnimationPlayer: its ".." root_node resolves the same tracks
	tree.anim_player = tree.get_path_to(model.find_child("AnimationPlayer", true, false))
	tree.set("parameters/gait/blend_amount", clampf(inverse_lerp(WALK_SPEED, RUN_SPEED, speed), 0.0, 1.0))
	tree.active = true


func _physics_process(delta: float) -> void:
	var to_target := _target.global_position - global_position
	to_target.y = 0.0
	var dist := to_target.length()

	_repath_clock -= delta
	if _repath_clock <= 0.0:
		agent.target_position = _target.global_position
		_repath_clock = repath_interval

	var want := Vector3.ZERO
	if dist > STOP_RANGE:
		var next_pos := agent.get_next_path_position()
		var d := next_pos - global_position
		d.y = 0.0
		if d.length_squared() > 0.0001:
			want = d.normalized() * speed

	_attack_clock -= delta
	if dist < ATTACK_RANGE and _attack_clock <= 0.0:
		tree.set("parameters/shot/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)
		_attack_clock = 1.2

	if avoidance:
		agent.velocity = want
	else:
		_move(want, delta)


func _on_safe_velocity(safe: Vector3) -> void:
	_move(safe, get_physics_process_delta_time())


func _move(v: Vector3, delta: float) -> void:
	velocity.x = v.x
	velocity.z = v.z
	velocity.y = -GRAVITY * delta if is_on_floor() else velocity.y - GRAVITY * delta
	move_and_slide()
	if v.length_squared() > 0.01:
		rotation.y = lerp_angle(rotation.y, atan2(v.x, v.z), minf(1.0, TURN_RATE * delta))
