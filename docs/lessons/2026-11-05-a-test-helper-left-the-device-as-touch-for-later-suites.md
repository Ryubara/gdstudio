---
areas: [tests, godot-ui]
---
# A test helper left the device as touch for later suites

2026-11-05

- **Saw:** Deadnight #1243's `godot (5)` failed `test_night_mouse_look` (turned 0.0, wanted over 0.01), a suite it did
  not touch. Alone it passed 3 of 3. After `test_lobby_framed_fit` it failed every time, on main too: the new suite
  had only moved the shards.
- **Cause:** `UiFitRun.set_window` sets `TouchMode.device_is_touch` for a phone page, and `restore()` put back the
  window's size and scale but not that. It came in with #1225, and each suite after a phone-page case then ran as a
  touch device.
- **Fix:** Deadnight #1251: `begin()` saves it, `restore()` puts it back, and a test fails if it stays set.
- **Check for next time:** when a helper gains a line that writes a static, its restore gains the matching line in the
  same change. A failure in a suite a pull request never touched is a reason to run the suites before it in the
  shard's order, not to rerun: the log gives the order, and a pair run settles it in a minute.
