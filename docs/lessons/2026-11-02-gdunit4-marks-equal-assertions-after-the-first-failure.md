---
areas: [tests, godot]
---
# GdUnit4 reported "Expecting 'x' but was 'x'" after the first failure

2026-11-02

- **Saw:** a scoreboard suite listed several failures whose expected and actual values were equal.
- **Cause:** once an assertion in a GdUnit4 test fails, the assertions after it in the same test are reported as failing
  too, even when their values match.
- **Fix:** read the first failure of a test and fix that; the later "x but was x" lines go away with it.
- **General:** with GdUnit4, only the first failing assertion of a test is evidence.
- **Docs:** the mistakes glossary (`gds lessons <area>`).
