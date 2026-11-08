---
areas: [godot, web, tests]
---
# A static cache read from another script's initialiser held its default, and the page played the drop

2026-11-06

- **Saw:** Deadnight #1320 found a probe bench, served with the probes asked for, playing the 6.5 s helicopter drop
  (`NightScreen.arrival_enabled` true, the touch layer down) while `WebProbe.asked()` read true a moment later. The
  menu path (`arrival_web.py --unasked`) was right, so the contract looked kept.
- **Cause:** `NightScreen.arrival_enabled`'s initialiser calls `WebProbe.asked()`, and the two scripts refer to each
  other. A bench that types its members (`var _night: Night`) loads the night screen first, so the initialiser ran
  while `WebProbe` was loading, before its own `static var _asked := -1`. The variable held the int default 0; `asked()`
  read 0 as "no". A log at the head of `asked()` showed the first call reading `2:0`.
- **Fix:** Deadnight #1323. `static var _asked: int` with no initialiser, 0 meaning unread (the same for
  `GamepadProbe._framed`), a scan test that fails for any game `static var` starting on a number other than zero, and
  `tools/web_smoke/arrival_bench.py`, which opens a night the way the benches do and fails if the drop plays.
- **Check next time:** a flag that is right on one path and wrong on another, and right a moment later, is a load
  order, not a race: log the variable's value at the first call. Say "not read yet" with the type's default, and
  never call another script's static function from a static initialiser. A probe that guards a contract runs it down
  the path the odd callers use, not only the menu.
- **Docs:** [Static variables and the order scripts load in](../engines/godot/static-variables.md).
