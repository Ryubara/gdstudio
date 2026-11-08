---
areas: [tests, godot]
---
# A GdUnit suite kept a freed node in a member variable across tests

2026-11-03

- **Saw:** the tests that built a map without its backdrop failed with `Invalid type in function 'setup' ... argument 3
  (previously freed) is not a subclass of the expected argument class`; the ones that built it first passed.
- **Cause:** a suite is one object for all its tests. `_backdrop` was set by an earlier test (an `auto_free` node, freed
  after it) and a later test that skipped the backdrop passed the stale reference on.
- **Fix:** reset every per-test member in `before_test` (`_backdrop = null`), never rely on "not set" meaning "not set by
  an earlier test".
- **Docs:** none needed beyond this lesson (the rule is general to GdUnit4: `docs/engines/godot/test-speed.md` has the suite
  shape).
