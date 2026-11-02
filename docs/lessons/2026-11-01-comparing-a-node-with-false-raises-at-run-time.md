# Comparing a Node with `== false` raised at run time

2026-11-01

- **Saw:** a Node compared with `== false` passed the parser and every unit test of the soldier voice (Deadnight #442);
  the night test, which runs the real night, stopped on it with a script error.
- **Cause:** GDScript does not reject comparing an Object with a bool when it parses; it fails only when the line runs
  with a live node, and the unit tests never reached that branch.
- **Fix:** test a node with `node == null` or `is_instance_valid(node)`, never against a bool, and keep a test that
  runs the real game path.
- **Docs:** none yet.
