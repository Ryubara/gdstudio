# Branches and worktrees

<!-- new section: moved out of starting-work.md when that page passed 45 KB (gdstudio #1539); the branch, the
     worktree, stacking, the sweep and a takeover are one subject -->

How an issue's branch and worktree are made, kept and removed: the part of [Starting work](starting-work.md) after
the issue is started and before the agent is.

## The branch and worktree {#worktree}

An agent never makes its own branch. A mistake in a hand-made branch or merge is found after the push, where fixing it
takes a force push (the maintainer's) or a new pull request
([Writing checks](writing-checks.md#same-input)).
So `gds issue start` sets the work up first, once the window has allowed the start and before anything on GitHub
changes:

1. fetches `origin/main` of `<workspace>/repos/<repo>` and creates the branch from it in
   `<workspace>/worktrees/<repo>/<branch>`, with absolute paths and without tracking `main` (`git worktree add
   --no-track`). The branch is named from the issue title (`tools: Add a thing` is `tools-add-a-thing`; `--branch`
   chooses another). A branch or folder that exists is refused;
2. checks that the git hooks of the repository (`pre-commit`, `commit-msg`, `pre-push`, written by `pre-commit
   install`) are installed, installs the ones that are missing, checks again, and runs the `pre-push` hook once
   (`git hook run pre-push`) so a hook that dies on this machine is found now. A repository with no
   `.pre-commit-config.yaml` has none to check. On Windows, Git LFS's own `pre-push` (`#!/bin/sh`) is moved aside by
   `pre-commit install` and then fails every push with `Executable /bin/sh not found`; the start rewrites its
   shebang to `#!/usr/bin/env sh`;
3. installs the pinned Godot addons (GdUnit4, the MCP addon) into the worktree's Godot project (`game/` in a game,
   `godot/` in the kit), untracked as `gds workspace init` installs them
   ([Integrations](workspace.md#integrations)); a reused worktree gets the ones it lacks. An addon not fetched yet is
   named in the output (`gds workspace init` fetches it) and the start goes on;
4. records the worktree in the ledger and prints `Worktree: <absolute path>` for the prompt.

If the worktree cannot be made, or a hook stays missing, the issue is left as it was and the worktree and branch it
made are removed; if GitHub fails after the worktree exists, it is removed too. `--no-worktree` skips the step for an
issue that needs no code. For a `PR:` task the agent adds a worktree of the pull request's branch itself, with an
absolute path (`git -C <workspace>/repos/<repo> worktree add <workspace>/worktrees/<repo>/<branch> <branch>`): a
relative path with `git -C` resolves inside the repository.

- **Approach:** Set up everything an agent needs before it starts (branch and worktree from fresh `origin/main`,
  verified pre-commit, commit-msg and pre-push hooks, a merge helper) and keep one function behind every copy of a rule,
  so a mistake is caught locally and never needs a force push. **Watch out for:** agents made their own branches and
  merges; the local commit-msg check dropped the `#` lines that git keeps with `--no-edit`, so a merge's `# Conflicts:`
  paragraph passed locally and failed CI on the stored commit (Deadnight #503 became #531). **Seen:** gdstudio #107,
  2026-11-02 (fix: `gds issue start`, a pre-push hook that runs CI's message functions on the stored commits, and `gds
  merge-main` ([Writing checks](writing-checks.md#same-input))).

### A branch stacked on another {#stacked}

<!-- new section: nothing said what a pull request built on an open branch carries (kit #1303) -->

Work that builds on a branch not landed yet starts from that branch, and its pull request against `main` carries the
base branch's commits as well as its own. Its `Model:` line names the model of every co-author trailer on those
commits, and its `Read first:` line the sections the base's author read that are on `main` (one the base adds waits
for the base to land: [anchors](rules.md#anchors)). `gds pr check-body` runs the CI `commits`
check on the branch's commits since `origin/main` and refuses a `Model:` line that misses one ([the body
guard](pull-requests.md#pr-body)); run it before `gh pr create`. The base's commits stay on the list after the base
lands (a squash merge makes a new commit on `main`), so the line keeps naming their models.

- **Approach:** When the base has landed as a squash, merge `main` into the stacked branch, put `main`'s whole tree in
  the merge (`git read-tree --reset -u origin/main` while the merge is open), re-apply only the branch's own change
  (`git diff <the last base head it merged> <branch tip> | git apply --3way`) and resolve what is left. **Watch out
  for:** a plain merge conflicts in every file of the base that changed before it landed (37 files, most of them the
  base's own and none of them the stacked branch's), and resolving them by hand risks keeping an old side of the base;
  the re-applied patch conflicted in 10 files, all the branch's own, and three of those `main` had since taken whole.
  **Seen:** gdstudio #1267 on #1040, 2026-11-12; PR #1505 on #1436, 11-14.
- **Approach:** While the base is still open, fetch it and merge its head into the stacked branch right after
  `main`, before resolving any docs fold or rebuilding anything solved on the base's files; where both merged the
  same `main`, take the stacked branch's code and the base's docs with the branch's own lines added. **Watch out
  for:** the base's agent works at the same time: it had merged the same `main`, rebuilt its clips on the new hold
  and folded its page into another section while the stacked branch was resolving `main` alone, so the fold made
  there (a section of its own) was redone into the base's section, and the clip that joins the base's would have
  been solved on the base's old files. **Seen:** gdstudio #1265 on #1191, 2026-11-12.
- **Approach:** When merging an open base into a stacked branch conflicts in one hunk of a file, resolve that hunk
  only (or take `main`'s file and re-apply the base's diff of it, `git diff origin/main...<base> -- <file>`), then
  check `git diff origin/main -- <file>` shows nothing but the base's change. **Watch out for:** `git checkout --theirs`
  takes the base's whole file, which is `main`'s file from before the base last merged it: it dropped #1444's cost
  work in `gait_transitions.gd` (three other hunks, merged cleanly by git on its own) while keeping the base's one
  line, and only the diff against `main` showed it. **Seen:** gdstudio #1431 on #1432, 2026-11-13.
- **Approach:** Commit the merge of an open base branch with a message file that ends in the trailer (`git commit
  --cleanup=strip -F <file>`); `gds merge-main` covers only `main`. **Watch out for:** after resolving conflicts,
  `git commit --no-edit` leaves git's `# Conflicts:` list as the last paragraph, so the commit-trailers hook refused the
  merge. **Seen:** gdstudio #1436 on #1456, 2026-11-13 (twice: the second agent on the task did it again on its
  first merge of the base).
- **Approach:** Before reading the CI of a pull request stacked on a parked branch, merge `main` into it (`gds
  merge-main`, and retarget it to `main` if it targets the base's branch); read a red check first as a fix `main` has
  and the base was cut before. **Watch out for:** a stacked branch carries `main` only as of its base, so the fixes
  `main` took after the base was cut are missing: #1455's fix of the parts budget flake was not in #1482, and
  `test_parts_budget` failed there as if the branch had broken it. **Seen:** gdstudio PR #1482, 2026-11-14.
- **Approach:** Another way to refresh a stacked branch after its base landed as a squash: rebuild the tree the base had
  on the `main` it last merged (`git merge-tree --write-tree <base head> <that main>`), diff that tree against the
  branch head (`git diff <tree> HEAD > own.patch`, the branch's own change alone), and apply it on a branch from
  `origin/main` with `git apply -3 own.patch`; resolve only what conflicts there. **Watch out for:** a plain merge of
  `main` meets every file the base touched, and a patch taken from the base's tip alone carries the `main` the base
  merged, so either way the base's old side can come back. **Seen:** gdstudio PR #1456, 2026-11-14 (on #1437; `main`'s
  side of each of #1437's files kept, only the branch's change on top).
- **Approach:** Before refreshing a stacked branch whose base has landed, look on `main` for the same fix landed by
  another route (`git log origin/main -S <a name the fix adds>`, the tests that read it), and keep only what `main`
  lacks. **Watch out for:** #1482's fix was already on `main` through #1432's `_asked`, so a merge of its own copy would
  have kept two ways to one result; the pull request became a test and a tour only. **Seen:** gdstudio PR #1482,
  2026-11-14.

### The worktree is removed when the work is finished {#sweep}

Nobody removes a worktree by hand: `gds worktree sweep` does it once the pull request merged or the issue closed (and
for detached reviewer and probe worktrees after hours without a touch), keeping loose artwork, notes and probes in
`scratch/<repo>/<branch>/kept/` ([the rules](workspace.md#sweep)). It never removes a worktree a process uses, one with
commits on no remote branch, or one touched in the last half hour. Work that must outlive the worktree is committed or
written to `scratch/`.

### A takeover reuses the worktree {#takeover}

When an agent stalls and another takes the issue (`gds issue release <ref>`, then `gds issue start <ref> --agent
<new>`),
the work is in the old agent's worktree: commits and uncommitted edits. `start` first looks for a worktree the issue
already has and hands that one over instead of making an empty one. An issue's worktree is a folder directly under
`<workspace>/worktrees/<repo>/` that is the checkout of a branch named for it, in this order of knowing:

- `--branch <name>`, when given (then only that branch counts);
- otherwise the branch the ledger recorded for the issue (a start that was not released), the branch that the title
  gives (`ui: Fix quick join` is `ui-fix-quick-join`) and that name with the issue number (`ui-fix-quick-join-526`).
  A branch the ledger records for a different issue is not taken, even when the two titles make the same name.

`release` removes the issue from the ledger, so after a release the branch name from the title is what finds the
worktree. Then:

- **One match:** it is reused as it is (nothing is fetched, merged, reset or cleaned). The git hooks are checked
  and installed like for a new worktree (step 2 above), and the output says how much work is in it (`N commit(s) ahead
  of origin/main, M changed file(s) not committed`), prints `Worktree: <path>` and records it in the ledger. If the rest
  of the start fails, a reused worktree is never removed (it holds work).
- **More than one match** (for example both `x` and `x-526`): the start is refused and names each branch and folder.
  Remove the ones that are not wanted with `git worktree remove`, or pass `--branch <name>` for the one to continue.
- **None:** a new branch and worktree, as above. A branch with no checkout under `worktrees/<repo>/` is not a
  worktree to reuse; it is refused or renamed as before.
- **`--fresh`:** skips the search and makes a new branch and worktree even when the issue has one (the old one is left
  alone; the new branch gets the issue number, `<slug>-<N>`). Use it to restart the issue from `origin/main`.

The agent that continues merges `origin/main` into the reused branch with `gds merge-main` (it may be behind).

An issue with an open pull request has no such takeover: `start` refuses it, and `release` leaves it in progress,
because
the pull request still closes it. Skip both. Give the new agent `PR: <owner/repo>#N` and the `Worktree:` line of the old
one, whose folder is the pull request's branch.

- **Approach:** Once an agent has handed over (at its retire line, its notes written), send new work only to its
  successor, and stop the old agent itself (TaskStop on its agent id), not only its background tasks, before the
  successor starts. **Watch out for:** a retiring agent at its context limit was sent a new task (record videos),
  then a fresh agent was started on the same work after only the old one's background CI wait was stopped; ending
  that task woke the old agent, which read the queued message and began writing the same files as the new one
  (`mannequin_parade.gd`) until the new agent noticed and stood down. **Seen:** gdstudio #1149 (PR #1172),
  2026-11-11 (a coordinator mistake).
- **Approach:** To restart an issue already started whose old branch `main` has overtaken (its work landed another way,
  or merging `main` would cost more than starting again), run `gds issue start <ref> --agent <name> --fresh`: a new
  `<slug>-<N>` branch and worktree from `origin/main`, recorded in the ledger; never call the start's worktree code or
  `git worktree add` yourself. **Watch out for:** nothing said when to use `--fresh`, so the agent on #1473 made its new
  worktree by calling the worktree code directly, around the start's checks and its ledger. **Seen:** gdstudio #1473
  (found on #1511), 2026-11-14.
- **Approach:** When the worktree the ledger records for your issue is another pull request's branch, run `gds issue
  release <ref>` and then `gds issue start <ref> --agent <name> --fresh` (the start still keeps the window's order); if
  an open pull request still closes the issue, it stays in progress: report that rather than make a worktree by hand.
  **Watch out for:** `--fresh` alone was refused ("is already in progress"), since the label and the ledger still held
  the first start, and nothing said how to get a worktree of your own. **Seen:** gdstudio #1525 (PR #1536), 2026-11-14.
