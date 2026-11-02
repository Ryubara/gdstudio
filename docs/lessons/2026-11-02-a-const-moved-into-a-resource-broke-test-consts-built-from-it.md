---
areas: [tests, godot]
---
# A const moved into a resource broke a test's `const` that was built from it, and one parse error stopped the run

2026-11-02

- **Saw:** after moving `HudFuel.IN_TIME` and its neighbours into a `.tres`, the GdUnit run ended with exit code 105
  and no failed test, only `SCRIPT ERROR: Parse Error: Assigned value for constant "TOTAL" isn't a constant
  expression.` in the log. The whole `tests/ui` folder did not run.
- **Cause:** a test file declared `const TOTAL := HudFuel.IN_TIME + HudFuel.HOLD_TIME + HudFuel.OUT_TIME`. A rewrite
  of every `Class.CONST` to `Resource.current().field` made it a call, and a `const` must be a constant expression.
  A parse error in one suite is not a red test: the summary is simply missing.
- **Fix:** turn such a `const` into a function or a local `var`, then read the log for `Parse Error` and check the
  executed-suites count matches the folder, not only the failure count. Before rewriting, grep the tests for
  `^const .*<MovedClass>\.`.
- **Docs:** [Resources you edit in the inspector](https://github.com/Ryubara/deadnight/blob/main/docs/research/inspector-resources.md)
  (Deadnight, #415).
