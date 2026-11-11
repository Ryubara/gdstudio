class_name AiAuthority
extends RefCounted
## Where the AI runs: only in the process that steps the world (a `NetServer`, or a game played
## offline). A client of a server draws the AI from the server's snapshots (`AiReplica`) and runs
## none of it: when it joins, `hand_over` takes the AI out of its map (the `AiDirector` and every
## `AiCharacter`, with their senses, brain, tasks and navigator), and an AI character that enters
## that map later takes itself out in its `_ready` (`runs_here`), before any of its processing.
##
## Decided by the map, not the process: one process may hold a server's map and clients' maps (a
## test, a capture), and only the clients' lose their AI. Plain code with no node.

## The meta a client's map root carries once it handed its AI over.
const REMOTE_META := &"ai_remote"


## Takes the AI out of the map under `map_root` (a client joined a server): frees its directors
## and AI characters at once, before any of them processes a frame, and marks the map so a
## character added later does the same. Answers how many nodes it freed.
static func hand_over(map_root: Node) -> int:
	if map_root == null:
		return 0
	map_root.set_meta(REMOTE_META, true)
	var found: Array[Node] = []
	for node in map_root.find_children("*", "", true, false):
		if node is AiDirector or node is AiCharacter:
			found.append(node)
	# A character inside another found one goes with it.
	var freed := 0
	for node in found:
		if is_instance_valid(node):
			retire(node)
			freed += 1
	return freed


## Whether the AI runs where `node` is: false inside a map that handed its AI over.
static func runs_here(node: Node) -> bool:
	var at := node
	while at != null:
		if at.has_meta(REMOTE_META):
			return false
		at = at.get_parent()
	return true


## Stops `node` and everything under it from processing and frees it; `detach` takes it out of
## the tree at once (not from its own `_ready`, while its parent is still adding it).
static func retire(node: Node, detach := true) -> void:
	node.process_mode = Node.PROCESS_MODE_DISABLED
	if detach and node.is_inside_tree() and node.get_parent() != null:
		node.get_parent().remove_child(node)
	node.queue_free()
