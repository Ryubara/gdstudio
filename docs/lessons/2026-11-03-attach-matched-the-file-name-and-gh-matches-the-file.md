---
areas: [tools, process]
---
# The attach guard matched the file name; `gh` matches the file, so pull requests still reached CI with local images

2026-11-03

- **Saw:** Deadnight #611, #637 and a dozen more pull requests reached CI with `![before](./before-desktop-2-solo.png)`
  in `## Screenshots` and the uploads appended after `## AI use`. `pr-rules` failed with "the 'Before:' capture is
  missing" and the coordinator edited each description by hand. The PreToolUse guard (`check_attach`, `check_body`)
  was in place and had passed all of them: the agents' own transcripts show `gds pr check-body` refusing the body
  ("the 'Before:' capture is missing"), then `gh pr create --attach` being let through at once, and the PowerShell
  tool is hooked like Bash (`matcher: "*"`, `SHELL_TOOLS`), so it was not a path the guard could not see.
- **Cause:** the guard and the docs believed `--attach` rewrites a `](./x.png)` reference "by file name". It does not:
  `gh` (2.102.0) rewrites a reference only when it names the **same file** as an `--attach` path, both read from the
  folder `gh` runs in. The agents ran the command in the worktree with `--attach <scratch>/x.png` and a `./x.png`
  reference: two files. The guard compared names, saw `x.png` twice and said yes. Measured with `gh issue edit
  --attach` (shared code), eight cases (the table in `docs/hooks.md#attach-paths`): only a pair that resolves to one
  file is rewritten. The kit's own tests had the same blind spot (`cd sub && ... --attach <tmp>/before.png` was
  expected to pass), so the wrong rule had a green test.
- **Fix:** `file_key` places the reference and the `--attach` path the way `gh` does (following a plain `cd`, `pushd`,
  `Set-Location`; an unfollowable `cd` leaves a relative path unplaced) and `check_attach` and `as_uploaded` compare
  files, not names. The refusal names both paths and the folder `gh` would read, and says to `cd` into the images'
  folder and attach `./<file>`, or to write the same absolute path in the body. A `PostToolUse` read-back
  (`check_opened_body`) is the second line for paths the guard cannot read (a script that runs `gh`): it fetches the
  description after a pull request is opened and names any `./` image reference left in it.
- **Check for next time:** a guard that predicts what a tool will do is tested against the tool, not against our idea
  of it. Before writing the rule, run the real command on something disposable (`gh issue edit --attach` on a scratch
  issue, body restored after) and write the measured table into the docs; a test that encodes the rule must fail on
  the case that went wrong in production (here, the command run in a different folder from the images).
- **Docs:** [Hooks: which paths the image guard covers](../hooks.md#attach-paths), [Capture](../capture.md#attaching).
