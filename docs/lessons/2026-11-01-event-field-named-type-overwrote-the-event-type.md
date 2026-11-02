---
areas: [gameplay, tests]
---
# An event field named `type` silently replaced the event's own type

2026-11-01

- **Saw:** `Invalid access to property or key 'hit_chance' on a base object of type 'Nil'` in code reading a rules
  event: `event["type"]` was a zombie type (`crawler`), not the event name (`zombie_changed`), so the match arm and
  the lookup both went wrong.
- **Cause:** events are dictionaries built as `{"type": event_name}` and then `merge(fields)`; a field called `type`
  overwrote the name without any error.
- **Fix:** no event field may be called `type` (the zombie's is `zombie_type`). A test checks that every event's
  `type` is still its own name.
- **Docs:** Deadnight `docs/design/rounds.md` (the event tables).
