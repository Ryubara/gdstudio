---
areas: [tests]
---
# A new source scan failed an older scan because its test strings held the calls the older one looks for

2026-11-05

- **Saw:** Deadnight's new scan of `tests/ui` for suites that push the night screen without choosing the helicopter drop
  passed alone. Run in the whole folder (a windowed baseline of every suite), `test_suites_leave_the_router_empty`
  failed: "these suites open a screen and never call `RouterFixture.clear(`": the new scan's own file.
- **Cause:** both scans read every suite's source as text. The new one has assertions that hold example text such as
  `UIRouter.push(NIGHT, ...)` to show the scan bites, and the older scan took those strings for a real call. The older
  scan already exempts itself and the fixture for the same reason; nobody added the new file.
- **Fix:** add the new scan to the older one's `EXEMPT` list. Before opening a pull request that adds a source scan,
  run the other scans that read the same folder (`grep -l "FileAccess.get_file_as_string" game/tests`) and the whole
  folder once. A second trap in the same scan: a pattern that looks for `NightScreen.arrival_enabled =` was satisfied by
  the line that puts the old value back (`= _arrival`), so a suite that never chose passed; the pattern is now
  `= (false|true)`, and the teeth were shown by removing the switch from a suite and by setting it in a suite on the
  allowlist (both fail the scan).
- **Docs:** Deadnight `docs/research/windowed-ui-ci.md` (the guard and the scheduled run);
  [Windowed GdUnit on a Linux runner](../godot/windowed-gdunit-on-linux.md) for the run itself.
