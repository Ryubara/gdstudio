# Merging on a red main

<!-- new section: hooks.md has under 2 KB left of its 50 KB limit, and no section there says how a merge guard tells a
fix forward from the rest; the hold took the same way out (gdstudio #1202) -->

## No merge while the default branch is red {#red-main}

When a watched workflow fails on the default branch, `.github/workflows/ci-failure.yml` opens an issue titled
`CI failing on the default branch: <workflow>` (`P-critical`). Until it closes, nothing lands but its fix:
every merge on top of a red `main` hides which change broke it and makes the next fix harder
([Landing](landing.md#landing)).

- **The guard** (`check_red_main` in `.claude/hooks/guards/red_default.py`) refuses a merge command, `gh pr merge`
  with or without `--auto` and a write to `gh api .../pulls/<n>/merge`, while an issue of that title is open in the
  pull request's repository. The refusal names each open issue and points at
  [Starting work: landing](starting-work.md#landing). It reads the repository from `-R`, from the API path, or from
  the pull request's address.
- **The fix forward lands.** A pull request whose body closes one of the open red issues by a GitHub closing keyword
  (`Fixes #1230`, `Closes #1230`, `Fixes owner/repo#1230`) passes. With two red issues open, a fix for either one
  lands, so neither fix waits on the other. A mention (`Refs #1230`, `after #1230 lands`) is not a fix.
- **Merging main into a branch is no merge command:** `git merge`, `gds merge-main` and the push after them are
  never judged, so a branch is refreshed while `main` is red, and after the fix lands it merges `main` and lands as
  usual. `gh pr merge --disable-auto` and a `GET` of the merge path pass too.
- **How it asks.** It lists every open issue of the repository (`gh issue list --state open --limit 1000`, about
  0.6 s) and matches the title, never the search: the search index can lag an issue filed seconds ago, and a label
  can be taken off. With the repository known the list comes first, so a green `main` costs one call; the pull
  request's body is read only when a red issue is open. When GitHub cannot be asked the call goes through with a
  warning naming the command to check by hand, as the behind-main guard does.
- **Where it stops.** It reads shell commands, like every guard here, so a script that calls the API itself is not
  seen; GraphQL merge mutations are already refused by [the hold guard](hooks-hold.md#hold). The tests are
  `python/tests/hooks/test_hook_red_main.py`; the other hook suites stub `red_main` as green.
