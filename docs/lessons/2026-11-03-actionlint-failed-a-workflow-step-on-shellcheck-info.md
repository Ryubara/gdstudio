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
- **Docs:** none beyond this lesson; the existing steps use `! grep` only as the last command of a script.
