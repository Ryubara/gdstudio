---
areas: [ci, tools, process]
---
# A local check judged the commit message draft; CI judged the stored commit

2026-11-02

- **Saw:** Deadnight #503's merge commit `e184e9eb` passed the local `commit-msg` hook and failed `pr-rules`. The fix was
  a force push, which the hooks refuse, so the pull request was replaced (#531); the same happened to #539 (#546). The
  maintainer asked: "Why do agents need to force push their branches? Wouldn't it be better for you to set all that up
  before you assign an agent to it?"
- **Cause:** two checks of one rule judged two different texts. The `commit-msg` hook is given the message file before
  git's cleanup, and `groundwork.py check-message` dropped every line that starts with `#` before checking, to ignore
  the help text git writes in the editor. But git only strips `#` lines when it opens the editor (cleanup `strip`);
  with `-m`, `-F` or `--no-edit` the cleanup is `whitespace` and a `# Conflicts:` list that `git merge` left in
  `MERGE_MSG` stays in the commit, after the trailer. CI reads the stored commit, so there the trailer was not in the
  last paragraph. Reproduced in a scratch repository: `git merge -m <message+trailer>` with a conflict, then
  `git commit --no-edit` stores `# Conflicts:` / `#<tab>file` after the trailer, and the hook's copy of the file has it
  too. The parser (`split_trailers`) was already shared; the difference was one line of input handling.
- **Fix:** `stored_message()` removes the editor's help text only (recognised by its first line, and by the scissors
  line of `--verbose`), every other `#` line counts, and `commit_problems` names a trailing `#` paragraph and the way to
  amend it. A `pre-push` hook (`groundwork.py check-push`) judges every commit of the push as stored, merges included,
  so the commit is still local when it is refused and `git commit --amend --cleanup=strip -F <file>` needs no force
  push. `gds merge-main` makes the merge without `--no-edit`.
- **General:** when a local check and a remote check apply one rule, make them one function over the same artifact (the
  stored object, not the draft or the file a hook is handed), and run the local one again at the last point before the
  push, where the object exists. A check that strips or normalises its input is a place the two can differ: test it
  with the real command sequence that makes the bad object, not with a string.
- **Also:** everything an agent needs to work cleanly is set up before it starts, because a mistake after the push costs
  a pull request: `gds issue start` makes the branch and worktree from fresh `origin/main` (absolute paths) and checks
  that the pre-commit, commit-msg and pre-push hooks are installed. An agent never makes its own branch.
- **Found on the way:** installing the `pre-push` hook broke every push in the kit checkout. Git LFS (our `.gitattributes`
  use it) had written its own `pre-push`; `pre-commit install` moves a hook that is there to `pre-push.legacy` and runs
  it itself, and on Windows its lookup of the LFS hook's `#!/bin/sh` fails (`ExecutableNotFoundError: Executable
  /bin/sh not found`). Installing hooks is not done until a hook has run: `gds issue start` now runs `git hook run
  pre-push` after installing, and rewrites that shebang to `#!/usr/bin/env sh`.
- **Docs:** [Starting work](../starting-work.md#worktree), [Hooks](../hooks.md#pre-push).
