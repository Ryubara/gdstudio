class_name AiNavAgentQuery
extends AiNavQuery
## The `AiNavigator`'s AGENT backend: a `NavigationAgent3D` child of the navigator, its target set
## on the navigator's own timer (never every tick: that makes it dance) and its path read back
## with the link owners. Its RVO avoidance is what the navigator's RVO option turns on. It asks
## from the character's own position: a start of its own (the stuck ladder's nearest point of the
## mesh) is the server backend's.

## The agent, made by the navigator.
var agent: NavigationAgent3D


func _init(owner_node: Node) -> void:
	super()
	agent = NavigationAgent3D.new()
	agent.name = "NavigationAgent3D"
	# The navigator walks the path itself: the agent never asks again on its own.
	agent.path_max_distance = 1000.0
	agent.path_metadata_flags = (
		NavigationPathQueryParameters3D.PATH_METADATA_INCLUDE_TYPES
		| NavigationPathQueryParameters3D.PATH_METADATA_INCLUDE_OWNERS
	)
	owner_node.add_child(agent)


func ask(
	map: RID, _from: Vector3, to: Vector3, layers: int, max_polygons: int, path: AiNavPath
) -> void:
	agent.set_navigation_map(map)
	agent.navigation_layers = layers
	agent.path_search_max_polygons = max_polygons
	agent.target_position = to
	agent.get_next_path_position()
	var result := agent.get_current_navigation_result()
	path.assign(result.path, AiNavQuery.links_of(result))


func release() -> void:
	if is_instance_valid(agent):
		agent.queue_free()
