class_name AiSensePool
extends RefCounted
## The members of one group split by faction, shared by every `AiSenses` of the tree and built
## again when the group's count changes, every `REBUILD_TICKS` physics ticks (a faction edited
## live) and when the relationships table is built again, so
## a think walks only the factions it cares about (a grunt among 200 grunts looks at the 4
## players, not at 199 friends) and never asks the tree for the group itself.
##
## A node that joins or leaves the group changes its count, so the next look sees it; one freed is
## skipped by the senses (`is_instance_valid`). Positions are read by the think, never kept here.

## Physics ticks between two rebuilds of a group's pool.
const REBUILD_TICKS := 30

static var _pools: Dictionary[StringName, AiSensePool] = {}

## The faction index of each part (-1: no faction or no table).
var factions := PackedInt32Array()
## The nodes of each part, in the order of `factions`.
var nodes: Array[Array] = []
## Their faction members, in the same order (null for a node with none).
var members: Array[Array] = []
## The physics frame it was built on.
var frame := -1
## The relationships table's version it was built with (-1: none).
var table_version := -1
## How many nodes the group had.
var count := 0
## The physics frame it was last checked on (the later thinks of a tick take it as it is).
var checked := -1
## The table it was checked against.
var checked_table: AiRelations


## The pool of `group` in `tree`, built again when it is `REBUILD_TICKS` old or `table` changed.
static func of(tree: SceneTree, group: StringName, table: AiRelations) -> AiSensePool:
	var now := Engine.get_physics_frames()
	var pool: AiSensePool = _pools.get(group, null)
	if pool != null and pool.checked == now and pool.checked_table == table:
		return pool
	var version := table.version if table != null else -1
	if (
		pool == null
		or now - pool.frame >= REBUILD_TICKS
		or now < pool.frame
		or pool.table_version != version
		or pool.count != tree.get_node_count_in_group(group)
	):
		pool = AiSensePool.new()
		pool._build(tree, group, table, now)
		_pools[group] = pool
	pool.checked = now
	pool.checked_table = table
	return pool


## Builds every pool again at the next look (for a test or a tool that adds things and senses in
## one frame).
static func forget() -> void:
	_pools.clear()


func _build(tree: SceneTree, group: StringName, table: AiRelations, now: int) -> void:
	frame = now
	table_version = table.version if table != null else -1
	var found := tree.get_nodes_in_group(group)
	count = found.size()
	for node in found:
		var body := node as Node3D
		if body == null:
			continue
		var member := AiFactionMember.of(body)
		var index := -1
		if member != null and table != null:
			index = (
				member.refresh(table)
				if member.table_version != table.version
				else member.faction_index
			)
		var part := factions.find(index)
		if part < 0:
			part = factions.size()
			factions.append(index)
			nodes.append([])
			members.append([])
		nodes[part].append(body)
		members[part].append(member)
