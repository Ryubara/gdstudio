class_name AiNavAvoidance
extends RefCounted
## How an `AiNavigator` keeps off the other walkers: not at all, a separation push from the
## characters near it, or the navigation server's RVO.
##
## - SEPARATION adds a push away from every AI character nearer than `radius`, stronger the nearer,
##   to the direction the path asks for: deterministic, about 4 to 8 µs a character in a browser.
## - RVO hands the wanted velocity to an avoidance agent of the server (the agent node's own with
##   the AGENT backend) and walks the safe velocity it answers a tick later: 1 to 1.5 µs a
##   character, not the same on every machine (kit docs/engines/godot/crowds.md#ai-characters).

enum Mode { OFF, SEPARATION, RVO }

## The mode, set by the navigator.
var mode := Mode.OFF
## The distance (metres) the push reaches, and the RVO agent's radius times two.
var radius := 1.2

var _rid := RID()
var _agent: NavigationAgent3D
var _safe := Vector3.ZERO
var _has_safe := false


## Starts avoidance for `body` on `map` (an agent node to use instead of a server agent, or null).
func start(map: RID, body: Node3D, agent: NavigationAgent3D, speed: float) -> void:
	stop()
	if mode != Mode.RVO:
		return
	if agent != null:
		_agent = agent
		_agent.radius = radius * 0.5
		_agent.max_speed = speed
		_agent.avoidance_enabled = true
		_agent.velocity_computed.connect(_on_safe)
		return
	_rid = NavigationServer3D.agent_create()
	NavigationServer3D.agent_set_map(_rid, map)
	NavigationServer3D.agent_set_radius(_rid, radius * 0.5)
	NavigationServer3D.agent_set_max_speed(_rid, speed)
	NavigationServer3D.agent_set_position(_rid, body.global_position)
	NavigationServer3D.agent_set_avoidance_callback(_rid, _on_safe)
	NavigationServer3D.agent_set_avoidance_enabled(_rid, true)


## Stops it and frees the server agent.
func stop() -> void:
	if _rid.is_valid():
		NavigationServer3D.free_rid(_rid)
		_rid = RID()
	if _agent != null and is_instance_valid(_agent):
		_agent.avoidance_enabled = false
		if _agent.velocity_computed.is_connected(_on_safe):
			_agent.velocity_computed.disconnect(_on_safe)
	_agent = null
	_has_safe = false


## The direction to walk (flat, at most 1 long) for `wish` (flat, at most 1 long) at `speed`
## m/s, for `body` among `others` (the characters to keep off, the body among them).
func steer(body: Node3D, wish: Vector3, speed: float, others: Array[Node]) -> Vector3:
	match mode:
		Mode.SEPARATION:
			return _separate(body, wish, others)
		Mode.RVO:
			return _rvo(body, wish, speed)
	return wish


func _separate(body: Node3D, wish: Vector3, others: Array[Node]) -> Vector3:
	var push := Vector3.ZERO
	var at := body.global_position
	for node in others:
		# The list is kept between repaths: a character freed since is skipped.
		if not is_instance_valid(node):
			continue
		var other := node as Node3D
		if other == null or other == body:
			continue
		var away := AiNavPath.flat(at - other.global_position)
		var distance := away.length()
		if distance >= radius or distance < 0.0001:
			continue
		push += away / distance * (1.0 - distance / radius)
	if push == Vector3.ZERO:
		return wish
	return (wish + push).limit_length(1.0)


func _rvo(body: Node3D, wish: Vector3, speed: float) -> Vector3:
	var wanted := wish * speed
	if _agent != null:
		_agent.velocity = wanted
	elif _rid.is_valid():
		NavigationServer3D.agent_set_position(_rid, body.global_position)
		NavigationServer3D.agent_set_velocity(_rid, wanted)
	if not _has_safe or speed <= 0.0 or wish == Vector3.ZERO:
		return wish
	return (AiNavPath.flat(_safe) / speed).limit_length(1.0)


func _on_safe(safe: Vector3) -> void:
	_safe = safe
	_has_safe = true
