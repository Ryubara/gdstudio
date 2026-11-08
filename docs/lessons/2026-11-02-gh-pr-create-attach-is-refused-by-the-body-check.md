---
areas: [tools, process]
---
# `gh pr create --attach` was refused by the description check for the images it was about to upload

2026-11-02

- **Saw:** a visual pull request (`gameplay`) with `![before](./before.png)` and `![after](./after.png)` on the
  Before: and After: lines and `--attach` on the command was refused: "the 'Before:' capture is missing", "the 'After:'
  capture is missing". `gds pr check-body` said the same. A comment on the issue (to upload the images there first) is
  refused too (no comment is ever posted as the user).
- **Cause:** two guards read the same body and disagree. The attach guard (`check_attach`) wants every attached file
  referenced as `](./<file>)` inside `## Screenshots`; the description guard (`check_body`, the same function CI runs)
  only counts an already uploaded image (`https://github.com/user-attachments/...`) between Before: and After:, and
  never swaps in the references `--attach` is about to upload. A body that satisfies one fails the other.
- **Fix:** upload the images first on something that is not a comment: `gh issue edit <N> --body-file <file> --attach
  <png>...` on the issue the pull request fixes (its body gets the images in a "Result" section, which is also where
  the images belong: screenshots on issues too), read the `user-attachments` URLs back
  (`gh issue view N --json body -q .body`), write them into the pull request body, check it
  (`gds pr check-body <body> --title <title file> --repo <checkout>`) and run `gh pr create` with `--body-file` and no
  `--attach`. The real fix is in `check_body`: give it the `--attach` references as uploaded.
- **Docs:** [Hooks: pull request bodies](../studio/hooks.md#pr-body).
- **Fixed by:** kit #186: `check_body` in `.claude/hooks/guards.py` rewrites each `](./<file>)` reference to a file
  passed with `--attach` on the same command into an upload address before it asks the checker, so the body with
  `./` references and `--attach` passes both guards (tests in `python/tests/test_pr_check_body.py`). Two checks that
  read one input need one definition of that input: when a command changes the body (`--attach` uploads), every check
  judges the body as it will be after the command, not as it was written.
