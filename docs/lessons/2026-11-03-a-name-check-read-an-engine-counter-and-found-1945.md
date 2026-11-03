---
areas: [tests, godot]
---
# A name check read an engine-made node name and found "1945" in its counter

2026-11-03

- **Saw:** the second map's formula row 29 (no names, writing or props from another game's setting) failed on CI of a
  change to the lot's lights, with `@MeshInstance3D@31945 (1945)` as the offending node (Deadnight #878, issue #896).
  It passed on `main` and on the other pull requests of the hour.
- **Cause:** the row read every node's name for a list of words, "1945" among them. A node added without a name gets one
  from the engine, `@<Class>@<counter>`, and the counter counts every node the process made before, so the word appeared
  whenever the earlier suites happened to leave the counter passing through 1945.
- **Fix:** the check skips names that start with `@` (the engine's; a script cannot set `@` in a name, Godot strips it)
  and still reads every authored name and every `Label3D`'s text. The test makes a real engine name by adding an
  unnamed child, since setting `node.name = "@..."` by hand does not keep the `@`.
- **Check:** a test that reads node names reads only the names someone chose; anything with a digit in its word list,
  or a short word, will one day meet a counter or an index.
