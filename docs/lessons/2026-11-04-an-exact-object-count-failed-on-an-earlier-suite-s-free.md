---
areas: [tests, godot, ci]
---
# A test that compared the whole process's object count for equality failed when an earlier suite freed something

2026-11-04

- **Saw:** `test_objects_and_nodes_are_flat_after_many_throws` failed in a CI shard: expected 10053 objects, got 10052
  (Deadnight #1031). The trail grew nothing; one object an earlier suite owned went away during the throws. Moving
  suites between shards (#1018) changed which ones ran before it, so a test that had passed for weeks failed on one
  shard.
- **Cause:** `Performance.OBJECT_COUNT`, `OBJECT_RESOURCE_COUNT`, `OBJECT_NODE_COUNT` and `OBJECT_ORPHAN_NODE_COUNT`
  count the whole process, not the test, and `is_equal` fails on a fall as well as on growth. A leak only ever raises
  a count.
- **Fix:** read every monitor first (an assertion is an object of its own), then assert `is_less_equal(before)`. Teeth
  checked by keeping an orphan `Node` or a `StandardMaterial3D` per throw: the objects (and, for the node, orphans)
  assertions fail. Never `is_equal` a process-wide count; use growth with a slack (`before + SLACK`) or count
  something only the test can move (`get_tree().node_added`, a pool's own `live_count()`).
- **Docs:** [Performance review](../engines/godot/performance-review.md), "How to measure it".
