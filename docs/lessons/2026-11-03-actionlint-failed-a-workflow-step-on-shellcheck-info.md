---
areas: [ci]
---
# actionlint failed a new workflow step on two shellcheck notes

2026-11-03

- **Saw:** the `actionlint` check failed on a pull request that added steps to `ci.yml` and `bots-nightly.yml`, though
  `actionlint` run locally passed (Deadnight #968).
- **Cause:** the runner's actionlint runs `shellcheck` on every `run:` script and local installs often have none, so
  nothing is checked there. Two notes failed it: SC2251 for `! grep -E "^ERROR" log` followed by another command (the `!`
  skips errexit; it is fine only as the last line), and SC2015 for `[ -f x ] && cat x >> y || true`.
- **Fix:** `if grep -E "^ERROR" log; then exit 1; fi` and `if [ -f x ]; then cat x >> y; fi`. Install `shellcheck` before
  running `actionlint` on a changed workflow.
- **Again, 2026-11-04 (Deadnight #1112):** a new `run:` block with `echo "$(ls dir | wc -l)"` failed it (SC2012,
  info level) after `pre-commit run --all-files` and a local `actionlint` had both passed. Neither runs `shellcheck` on
  Windows. This runs both anywhere, and fails on the old file: `uvx --from shellcheck-py --with actionlint-py bash -c
  'actionlint .github/workflows/*.yml'`. Run it before the push of any workflow change; use `find ... | wc -l` to count.
- **Docs:** none beyond this lesson; the existing steps use `! grep` only as the last command of a script.
