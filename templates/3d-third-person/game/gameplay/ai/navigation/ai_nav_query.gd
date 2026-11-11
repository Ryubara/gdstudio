class_name AiNavQuery
extends RefCounted
## Asks the navigation server for a path, the `AiNavigator`'s SERVER backend: one
## `NavigationServer3D.query_path` with the link owners in the answer, the parameters and the
## result kept and filled again, so a query makes no garbage. No node is needed.
##
## `AiNavAgentQuery` is the AGENT backend, with the same `ask()`: a `NavigationAgent3D` asked on the
## same timer, for a game that wants the agent's RVO avoidance.

var _parameters := NavigationPathQueryParameters3D.new()
var _result := NavigationPathQueryResult3D.new()


func _init() -> void:
	_parameters.metadata_flags = (
		NavigationPathQueryParameters3D.PATH_METADATA_INCLUDE_TYPES
		| NavigationPathQueryParameters3D.PATH_METADATA_INCLUDE_OWNERS
	)


## Asks `map` for a path from `from` to `to` on `layers`, searching at most `max_polygons` (0: no
## limit), and puts it into `path`.
func ask(
	map: RID, from: Vector3, to: Vector3, layers: int, max_polygons: int, path: AiNavPath
) -> void:
	_parameters.map = map
	_parameters.start_position = from
	_parameters.target_position = to
	_parameters.navigation_layers = layers
	_parameters.path_search_max_polygons = max_polygons
	NavigationServer3D.query_path(_parameters, _result)
	path.assign(_result.path, links_of(_result))


## Releases what it holds (nothing for the server backend).
func release() -> void:
	pass


## For each point of `result`, the instance id of the link that starts there, or 0.
static func links_of(result: NavigationPathQueryResult3D) -> PackedInt64Array:
	var links := PackedInt64Array()
	var types := result.path_types
	var owners := result.path_owner_ids
	links.resize(result.path.size())
	for index in mini(types.size(), links.size()):
		if types[index] == NavigationPathQueryResult3D.PATH_SEGMENT_TYPE_LINK:
			links[index] = owners[index] if index < owners.size() else 1
	return links
