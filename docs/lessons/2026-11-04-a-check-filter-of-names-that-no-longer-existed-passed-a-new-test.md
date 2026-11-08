---
areas: [tests]
---
# A check filter of names that no longer existed passed a new test

2026-11-04

- **Saw:** a new Deadnight test of the arms (#987) passed at once, with a gun still 59 mm in the other arm.
- **Cause:** the checks had been split for a diagnosis, with new names, and the test filtered by the old names; a filter
  that matches nothing measures nothing and reports no fault.
- **Fix:** put the checks back and see the test fail before trusting it. A test that filters a table by name either
  asserts the names are in the table or is seen red once.
- **Docs:** [Learn in the same session](../studio/hooks.md#learning).
