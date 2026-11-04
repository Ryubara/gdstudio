---
areas: [tests, input]
---
# A look suite read no turn at all because an earlier suite left the main menu on the router

2026-11-04

- **Saw:** `test_look_window_size.gd` failed with the same 24 failures on two unrelated Deadnight pull requests
  (#1037, #1038; "turned 0.0000 rad, the hand asked for -2.0570", and 0.0 against -0.22 for the touch look), while `main`
  stayed green. Alone, and after the two suites that ran just before it, it passed. Running the whole shard in the
  job's order reproduced it locally (600 cases, 24 failures).
- **Cause:** `test_input_matrix.gd` enters a night through `UIRouter.reset(MENU)` and `UIRouter.push(NIGHT)` and pops
  the night, which leaves the main menu on the shared router with a button focused. That screen is full rect with
  a stopping mouse filter, so a mouse motion sent through `Input.parse_input_event` never reached the player's
  `_unhandled_input`; calling that handler directly turned the view. The shards are dealt by measured seconds, so
  whether a suite that clears the router ran between the two depended on the day's times: `main` had one, the two
  pull requests did not. The same cause as the lessons below, a third time.
- **Fix:** the suite ends with `RouterFixture.clear` (Deadnight #1039), found by bisecting the suites before it
  (`input_matrix` + the look suite alone failed) and printing the router's depth and the focus owner. A scan test,
  `tests/ui/test_suites_leave_the_router_empty.gd`, fails any suite that calls `UIRouter.reset|push|replace` or loads
  `res://main.tscn` without `RouterFixture.clear`, so the next such suite is red in its own pull request, in
  whatever order the shards fall.
- **Check:** a red suite that reads "no input" only in a shard: reproduce with that shard's order (the job log prints
  it after `shard N:`), then print `UIRouter.depth()`, `get_viewport().gui_get_focus_owner()` and `UIRouter.busy`
  before the first event. A suite that shows a screen clears the router when it ends.
- **Docs:** [a suite that ends on a router screen eats later clicks](2026-11-02-a-suite-that-ends-on-a-router-screen-eats-later-clicks.md),
  [a touch suite left the emulated mouse button down](2026-11-02-a-touch-suite-left-the-emulated-mouse-button-down-for-the-next-suite.md).
