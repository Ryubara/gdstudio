---
areas: [tests, godot]
---
# A test counted events in a lambda and read zero

2026-11-02

- **Saw:** a GdUnit test with `var kills := 0` and an `on_event` lambda doing `kills += 1` always saw `kills == 0`,
  though the events came.
- **Cause:** a GDScript lambda captures a local variable by value when it is made; an `int`, `bool` or `float` it
  changes is its own copy. Arrays and dictionaries are shared, so appending to them works. **Assigning** a whole
  `Dictionary` or `Array` to the outer variable inside the lambda is the same trap (2026-11-04: `reopened =
  answer["lobby"]` in a polling lambda left the outer one empty and the next line failed on a missing key).
- **Fix:** collect into an `Array` (`kills.append(1)`, `kills.size()`, or a holder `held[0] = value`) or into a member
  variable of the test. The bot
  suites do so; a probe object (`CombatProbe`) holds the counts when there are many.
- **Docs:** none needed beyond this lesson.
