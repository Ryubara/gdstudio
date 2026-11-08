---
areas: [tests, godot-ui]
---
# The first-run hint list grew and two suites that compared with the list went red

2026-11-05

- **Saw:** after Deadnight #1286 added a fourth hint (the bots' tag) `test_touch_hints` and `test_popup_lane` failed:
  `showing() != TouchHints.ORDER`. The touch suites' own run found the first; the second is in another folder's
  suite and only the whole `tests/ui` run found it.
- **Cause:** both tests wrote "every hint is showing" as the constant that lists the hints, so a hint that shows only
  under a condition (a bot in the room) made the expectation false for a fixture without that condition.
- **Fix:** the tests name the hints that fixture can show (`WITHOUT_BOTS`), and the new hint has its own suite for the
  condition. Run all of `tests/ui` in parts after adding to a shared list; grep the tests for the constant first.
- **Docs:** [Touch controls](../engines/godot/ui-controls.md#touch-controls).
