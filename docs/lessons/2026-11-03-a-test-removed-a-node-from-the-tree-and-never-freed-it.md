---
areas: [tests, godot]
---
# A test removed its HUDs from the tree and never freed them, and the run read "0 failures" with 298 orphans

2026-11-03

- **Saw:** a UI suite run by hand ended `Overall Summary: 767 test cases | 0 errors | 0 failures | ... | 298 orphans`, and
  was reported green; CI's leak gate then failed the whole shard on `298 orphans`, 296 CanvasItem RIDs, 1,529 ObjectDB
  instances and ShapedText and Font RIDs leaked at exit (Deadnight #746).
- **Cause:** the new test of a party of eight built a HUD with a fixture (`host.add_child(hud)`) and ended with
  `hud.get_parent().remove_child(hud)`. The host is `auto_free`d, but only frees the children it still holds, so a child
  taken out of the tree has no owner left and stays alive. The older test in the same suite did
  `remove_child` then `free()`; the copy forgot the second line. The orphan count sat in the same summary line as the
  failures, and the check read only the failures.
- **Fix:** free what you remove (`remove_child(node)` then `node.free()`, or `queue_free()` and await a frame), or leave
  the node in the host and let the `auto_free`d host take it. Every run of a suite also reads the `orphans` column: any
  number above 0 in a `Statistics:` line is a leak to fix before the pull request (`grep -E "[1-9][0-9]* orphans"`), the
  line names the suite that owns it.
