---
areas: [tests, audio]
---
# A resource-count test counted the deferred sounds an earlier suite had queued

2026-11-03

- **Saw:** `test_shot_effects_pool` (resources and objects held over a fight) failed with 2 failures only when run
  after the night suites in one process; alone, and in `tests/weapons` alone, it passed (Deadnight #823).
- **Cause:** the deferred sound banks (#864) queue their files on the `Audio` autoload, and it decodes a few ms of them
  every frame. The night warm-up tests fill that queue; the new guns' bank made it long enough to still be running
  inside the next suite, so its decoded sounds counted as the fight's own resources.
- **Fix:** a test that counts resources or objects waits first for `Audio.decode_pending()` to reach 0 (bounded in
  frames). Run such a test after `tests/night` once, not alone, before you trust it.
- **Documented:** `docs/research/web-export.md` ("Loading a night") names the deferred queue; this page is the test side.
