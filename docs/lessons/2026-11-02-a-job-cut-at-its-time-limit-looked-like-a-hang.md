---
areas: [ci, tests]
---
# A job cut at its time limit looked like a hanging test

2026-11-02

- **Saw:** Deadnight #488's `godot` job log ended on
  `test_night_shot_authority.gd > test_an_aim_origin_far_from_the_head_is_pulled_back_to_the_slack STARTED`, and the
  job was cancelled. It read as that test hanging.
- **Cause:** the job hit its `timeout-minutes` (20): it was cancelled 20 minutes after it started, 15 ms after that
  line printed. The cancel lands wherever the run happens to be, so the last line names an innocent test. The suite
  took 17 to 20 minutes, and the pull request's new tests added about 40 s.
- **Fix:** before suspecting the last test, compare the cancel time with the job's start plus its limit, and look for
  the longest gap between timestamps (a real hang leaves minutes). Then run the suite alone and its folder. Keep the
  limit well above the measured time (Deadnight #501 raised it to 30 minutes) and watch the suite's total.
- **Docs:** Deadnight `docs/research/ci-jobs.md`;
  [A pull request ran CI with its branch's old time limit](2026-11-02-a-pull-request-ran-ci-with-its-branchs-old-time-limit.md).
