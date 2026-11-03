---
areas: [tests, godot-ui, process]
---
# A test summary cut to 60 lines hid four failures, and one new settings row broke the Play screen's fit

2026-11-03

- **Saw:** Deadnight #715 passed my post-merge run (as I read it) and went red on `godot (3)`: the Play screen tests
  (`721 <= 720` at 720p, "needs 490, canvas has 540" on the phone) and `test_capture_quit` (my tour left a lambda in
  `MainMenu.board_factory`). All four also failed in my own run.
- **Cause:** my test script piped its output through `head -60`, so the first 60 matching lines (55 passes and two cost
  failures) were all I saw. Separately, a sixth settings row used the 50 units the Play screen's tests had left
  (headless allowance 100 against a 440 need), and I had only run the bots, night, rules, ui and net folders, not `core`.
- **Fix:** put the skill selector beside the Bots count in one row (the key `bot_skill` names that row), clear the
  hook in the tour, and test both. The real fit was checked with the tour at 1280x720 and 844x390.
- **Check for next time:** print the failure count and every `FAILED` line (`grep -c FAILED`, never `head` on a mixed
  list) and compare the `Overall Summary` line; run the whole `game/tests` before the pull request, not the folders you
  think you touched; before adding a row to a shared form, read the fit tests' headroom and capture the phone size.
