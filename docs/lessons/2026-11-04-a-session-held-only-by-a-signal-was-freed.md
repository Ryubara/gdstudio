---
areas: [gameplay, tests, godot]
---
# A listener held only by a signal connection was freed, and its test saw nothing

2026-11-04

- **Saw:** Deadnight #1058: a test called `_session(store)` for its first night, discarded the result, and the next
  line's night credited the profile as if the first had never listened (172 XP where 22 were expected). No error.
- **Cause:** a `RefCounted` that only a signal's Callable points at is not kept alive: the Callable holds the object's
  id, not a reference, so the object is freed when the last variable goes. The game keeps its session in a `var` of the
  `Night`, so only the test dropped it.
- **Fix:** keep the object in a variable for as long as it must listen (`var first := _session(store)`) and assert
  something on it, which also makes a dropped one fail loudly.
- **Docs:** [Lessons](index.md): no page covers it yet; this file is the record.
