# "Resources still in use at exit" from a RefCounted that connects lambdas to itself

2026-11-01

- **Saw:** a headless run ended with `ERROR: N resources still in use at exit` and `ObjectDB instances were leaked`,
  listing the rules scripts and their `.tres`.
- **Cause:** an object connects lambdas that capture itself to its own child's signals: a reference cycle that reference
  counting never frees. Two RefCounted objects connected to each other's signals do the same.
- **Fix:** give such an object a `dispose()` that disconnects (or do not capture `self` in lambdas) and have the owner
  call it; `--verbose` names the leaked instances. Fix it early: agents learn to skip the error, and it hides real
  leaks.
- **Docs:** Deadnight `docs/research/weapon-firing.md`.
