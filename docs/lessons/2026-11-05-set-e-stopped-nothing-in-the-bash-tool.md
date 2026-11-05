---
areas: [process, tools]
---
# `set -e` stopped nothing in the Bash tool, and a refused description went out

2026-11-05

- **Saw:** on kit #621 a script began with `set -e`, then ran `gds pr check-body`, `gh pr edit` and `gh pr ready`.
  `check-body` printed `description: refused` and exited 1, and the next two commands ran anyway: a description the
  rules refuse was published, and the pull request was marked ready. The required `body` check would have caught it
  after the push. Earlier in the same task, a commit refused by a hook was followed by a `git push` from the same
  script: it pushed nothing, and the output read as if the work had gone up.
- **Cause:** two gates failed together. In the Bash tool, `set -e; false; echo next` prints `next`, while the same
  lines run through `bash -c` or `bash <script>` stop at `false`. So the tool runs a command in a form where bash
  ignores `set -e`, as it does inside any `&&` or `||` list. The exit status was never at fault: three
  reproductions in a child `bash` all stopped. The hook on `gh pr edit` missed it too: `--body-file $S/body-b.md`
  reaches the hook with the variable unexpanded, it finds no such file, and a body it cannot read is not judged.
- **Fix:** in the Bash tool, put `|| exit 1` on each step that gates the next, chain them with `&&`, or run a script
  file with `bash <file>`, where `set -e` holds. Never rely on a `set -e` at the top of a command. Give `--body-file`
  a literal absolute path, not a variable, so the hook can read it. Check for next time: read each step's own output
  before the next step's, and treat a line of `refused` above a success as the failure it is.
- **Docs:** this page.
