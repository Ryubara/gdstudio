---
areas: [backend, tools]
---
# A probe of a deploy script reached the real Railway CLI and made a project in the account

2026-11-05

- **Saw:** while proving a retry of `railway up` (Deadnight #1269), an ad hoc command meant to run the old
  `deploy/web/deploy.sh` against a fake `railway` printed `Created project stage on Noah` and a real build log. `railway
  list` then showed a new project `stage`, and an older one with the same name from 2026-11-01.
- **Cause:** the fake was meant to be cut out of the test file with `awk`; the `awk` pattern failed on a backslash, so no
  fake existed and the real CLI, logged in as the maintainer, ran. With no `RAILWAY_TOKEN` and no linked project,
  `railway up <folder>` does not fail: it makes a project named after the folder (`stage`, the deploy scripts' default
  folder name) and uploads to it.
- **Fix:** the project was deleted by id (`railway delete --project <id> --yes`; Railway schedules the deletion). The three
  deploy scripts now refuse to run with neither `RAILWAY_TOKEN` nor a linked project (`railway status` fails), before
  anything is uploaded, and `deploy/test_railway_up.sh` has a case for it. Check for next time: a probe of a script that
  calls a real service puts its fake in a file under the scratch folder first, runs it with `PATH` set to it alone, and
  checks that `command -v <tool>` is the fake (or sets `RAILWAY_TOKEN=` empty so the guard stops a real run); a command
  built from a text cut that was not read back is not run against a logged-in account.
- **Docs:** the game's `docs/research/web-export.md` (Failures from outside).
