---
areas: [ci, godot-ui]
---
# Two merges crossed a line limit CI never reads

2026-11-05

- **Saw:** after Deadnight #1225 landed, the pushes of #1226, #1224 and #1223 were refused by `lobby_screen.gd:1006:
  Max allowed file lines num (1000) exceeded`, a file none of them changed. Main's CI stayed green.
- **Cause:** #1214 took the file to 996 lines and #1225 added 10; each passed alone. `gdlint` runs only in the local
  hooks, and no workflow runs it, so nothing judged the two together. The `pre-push` hook lints the files in the push
  range, so the first check of the merged file was the next branch to merge main across #1225. A branch cut from that
  main pushed without trouble (#1242), since the file was not in its range.
- **Fix:** Deadnight #1239 moves the seat rows out of the file; Deadnight #1238 adds `gdlint` to CI.
- **Check for next time:** a limit checked only on a person's machine is not a guarantee about main. When a push is
  refused for a file the branch never touched, read main first: every branch that merges main is blocked, so fix main
  before the next merge, and never push past the hook. A file near a limit (`night.gd` 971, `night_host.gd` 958) gets
  its split before the next pull request that grows it.
