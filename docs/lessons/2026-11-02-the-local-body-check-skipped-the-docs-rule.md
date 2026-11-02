---
areas: [tools, ci]
---
# The local body check said ok to a body whose docs rule CI refused

2026-11-02

- **Saw:** `gds pr check-body` (and the PreToolUse body guard built on it) printed `description: ok` for deadnight #612's
  body; CI's `pr-rules` then refused it: "docs: refused - code changed without a docs change; update the docs or add a
  line 'Docs: none'".
- **Cause:** `pr-rules` runs two checks, `check-body` (the text) and `check-docs` (the text plus the pull request's
  changed files). The local check ran only the first, so any rule that depends on the diff passed locally and failed
  after the push. "The same rules as CI" was true of the body text only.
- **Fix:** `pr.check_docs` (`python/src/gds_tools/pr.py`) runs the same `groundwork.py check-docs` on the files of
  `git diff --name-only origin/main...HEAD`; `gds pr check-body` and the guard use it. When the branch cannot be told
  (no commit, a detached head, the checkout is on main, no `origin/main`) it prints `docs: cannot tell` and never `docs:
  ok`; the guard does not refuse on that. The escape line is read exactly (`Docs: none`, nothing after it), because
  `pr-rules` reads it that way.
- **Check for next time:** when a local check stands in for a CI check, list every job of the CI check and what input
  each reads (text, diff, history, API); a job whose input the local check lacks is either added or reported as "cannot
  tell", never as ok.
- **Docs:** [Hooks](../hooks.md#pr-body).
