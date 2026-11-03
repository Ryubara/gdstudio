---
areas: [tests, godot]
---
# A node made only to read its property list leaked at exit

2026-11-03

- **Saw:** a GdUnit suite passed with `1 orphans` and the run ended with `ERROR: 2 resources still in use at exit`.
- **Cause:** `SomeNode.new().get_property_list()` in a test made a node that was never in a tree and never freed, with
  the materials its script had made.
- **Fix:** `auto_free(SomeNode.new())`; read the suite's orphan count and the log's last lines, not only the pass line.
- **Docs:** [test speed](../godot/test-speed.md).
