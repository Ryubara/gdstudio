---
areas: [tests, tools]
---
# A settings test failed in a whole-suite run because a second run of the project shared its user:// file

2026-11-02

- **Saw:** `test_settings_hardening > test_the_debounced_write_runs_while_the_tree_is_paused` failed in a whole-suite
  run (`file.load` returned 7, file not found; then `null` for the value) and I opened a flake issue for it (Deadnight
  #594), reading it as a slow-runner timing failure. It never failed in CI.
- **Cause:** I was running two whole-suite copies at once from one worktree. Every run of a project shares one `user://`
  folder, the suites write fixed names there (`user://settings_hardening_test.cfg`), and each test's setup and cleanup
  delete that file. One run's cleanup removed the file between the other run's write and its read. Running only the
  suite, twice at once, failed 3 of 6 on `main` with the same two assertions; once alone it never failed.
- **Fix:** the three settings suites name the file by process id (`QuietSettings.test_path`), so two runs never touch the
  same file; 6 of 6 concurrent pairs then passed. Eleven other suites still use a fixed `user://` name (listed in the
  pull request), harmless in CI (one run per machine) but a trap for agents that run suites in parallel.
- **Check for next time:** before filing a flake, reproduce it with nothing else of the same project running, and ask
  whether the failing test touches a path (`user://`, a port, a temp file) that a second run of the project shares. A
  failure that appears only while you run two copies is your own collision. Name test files by process, and give
  servers port 0.
