---
areas: [process, general]
---
# The "what done means" list was narrower than the issue's Summary, and a requirement was never built

2026-11-04

- **Saw:** Deadnight #1073 (poster sets) was reported finished with its tests and captures green. The coordinator read
  the issue and the design page against the pull request and found "a finished set in the night report" (the issue's
  Summary, and `docs/design/progression.md#poster-sets`: "and in the night report when finished") built nowhere: no
  report or credits file was in the diff, and the report to the coordinator did not list it as left out. The pull request
  of #1164 (a paid level reaching every tag and report) nearly merged without the night-report case too.
- **Cause:** the issue form's `What "done" means` list is a short checklist, and the work was checked against that list
  alone. The Summary and the design section say more than the list (here the night report), and "Not covered" was
  written from memory of what was built, not from the sentences that had been promised. A test suite and captures prove
  what was built; they cannot show a sentence nobody turned into a test.
- **Fix:** before calling a pull request done, walk every sentence of the issue's Summary and of the design section it
  points to, one line each: built (with the test that fails without it) or not built. Whatever is not built goes under
  `Not covered` in the report and in the pull request, and becomes an issue; nothing is left out silently. Where the
  feature has a second place it must show up (a menu card and the night report, the lobby and the scoreboard, online and
  solo), name each place in that walk. The walk found two real bugs here as well: a set finished by two feats in one
  event was told twice, and the finish was invisible to the solo night's report.
- **Docs:** [the starting-work page](../studio/starting-work.md) names the issue form; this file is the record.
