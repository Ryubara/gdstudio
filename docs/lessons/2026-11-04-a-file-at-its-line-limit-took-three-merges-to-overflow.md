---
areas: [process, godot]
---
# A file at its line limit overflowed on a merge, after each pull request had fitted on its own

2026-11-04

- **Saw:** Deadnight's `night.gd` stood at 995 of gdlint's 1,000 lines when #1125 landed, and #1128, #1129, #1136 and
  #1069 all had a reason to touch it. #1128 fitted when it was written, then came to 1,002 on one merge of main and
  1,003 on the next. The first time the coordinator tightened comments; the merge after that undid it.
  `night_host.gd` reached 1,003 the same way on #1129.
- **Cause:** a limit on a file is shared by every open pull request, and each one's checks only see itself plus main.
  Nothing says a file is nearly full until a commit is refused, and that commit is usually a merge, made by someone
  who did not write the code. Trimming comments buys a few lines and leaves the file full for the next one.
- **Fix:** when a file is within about 20 lines of a limit and more than one open pull request touches it, move a
  whole piece out instead of tightening what is there: #1128 moved `_ping_request` into `PingAim`, where its logic
  belonged, and `night.gd` went to 970. Tell any agent starting in that file. A brief is the only warning it gets.
- **Docs:** Deadnight #1128.
