---
areas: [godot, tests]
---
# "Resources still in use at exit" from a RefCounted that connects lambdas to itself

2026-11-01

- **Saw:** a headless run ended with `ERROR: N resources still in use at exit` and `ObjectDB instances were leaked`,
  listing the rules scripts and their `.tres`.
- **Cause:** an object connects lambdas that capture itself to its own child's signals: a reference cycle that reference
  counting never frees. Two RefCounted objects connected to each other's signals do the same.
- **Fix:** connect methods or `bind` callables instead of lambdas that use `self`: only a lambda that captures `self`
  holds the object strongly, so no `dispose()` is needed (Deadnight #207); `--verbose` names the leaked instances. Fix
  it early: agents learn to skip the error, and it hides real leaks.
- **Also:** quitting while a sound plays leaves its voice queued and reports leaked streams: stop audio and wait a few
  frames before quitting.
- **Second case, in a test (Deadnight #432):** a GdUnit test connected a lambda that captures the object it
  listens to (`rules.<signal>.connect(func(): ... rules ...)`). The object holds the connection and the lambda holds
  the object, so neither is freed: "resources still in use at exit" and leaked instances, and CI fails with every
  test green. Disconnect in `after_test` and drop the reference, or capture a `WeakRef`. A `node_added` lambda left
  connected does the same and also breaks later tests (Deadnight challenges, #429).
- **Find it:** run the suspect test file alone with `--verbose`; the leak count reproduces exactly (121 instances
  and 22 resources on #432).
- **Docs:** Deadnight `docs/research/weapon-firing.md`.
