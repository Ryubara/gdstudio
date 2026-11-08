# Starting work

Issues are worked from oldest to newest, at all times, and every start goes through one tool. Nobody sets
`S-in-progress` by hand and no agent starts on a request that has no started issue. The hooks enforce it
([Hooks: issue order](hooks.md#issues)).

## The rule

- Only the **window** may start: the `N` oldest open issues that are not in progress, blocked or waiting for
  information. `N` is 5 (`[issues] window` in the kit's `.claude/hooks/hooks.toml`); a game replaces it in its own
  `.claude/hooks.local.toml`.
- "Oldest" is the lowest issue number. Pull requests are not issues and are left out.
- Issues labelled `P-critical` come first, oldest first among them. Only the maintainer sets that label; the hooks
  refuse `--add-label P-critical` from a session.
- **A pull request needs no label.** If an open pull request closes an issue (`Fixes #N`, `Closes #N`), the issue is in
  progress and is never handed out again. Pull requests never carry `S-in-progress`.
- Out of the line: `S-in-progress`, `S-pending-review`, an issue an open pull request closes, `S-blocked`,
  `S-needs-info`.

## Everything that can run, runs {#parallel}

The coordinator keeps an agent on every issue that may start, in every repository of `workspace.toml`. An issue that is
not started has one of two reasons, and the reason is written down:

- **It conflicts** with an issue an agent has: both would edit the same files in ways a merge cannot settle, or one
  measures numbers the other is changing. Name the files. Give both to one agent in sequence; the second is blocked
  on the first.
- **It is blocked**: it needs something another issue or pull request makes (its `### Blocked by` section, its
  `Depends on:` or `Starts after` line names it), or it waits on the maintainer.

Working on the same subsystem is not a conflict, and neither is "the same agent takes them in order". Agents on one
subsystem run side by side: each keeps its change to its own part, adds new modules where it can, and merges
`origin/main` before each push. Before blocking one issue on another, read where the blocked issue names its
dependencies (below); if the blocker is not there and no file is named, start the issue. A chain of several issues
blocked on one running issue is the sign of a serial queue that should not exist.

Parallel pull requests still conflict when they edit the same lines, whatever order they merge in: merge order only
decides which one settles the clash, and auto-merge lands the first that goes green, not the oldest. So a fix several
of them need lands once (in the first, or on its own) and the others merge `main` after it instead of writing it
again; each adds its own rows to a shared docs table and never rewords another's; and the coordinator names the shared
files in each agent's prompt ([lesson](../lessons/2026-11-03-five-parallel-prs-edited-the-same-files-and-conflicted.md)).

`gds issue block` enforces that, so a block cannot be written on a reason it does not have. `--on "#N"` is accepted
when the blocked issue's body names #N as a dependency, or when `--conflict <path>...` names the files both would edit
in ways a merge cannot settle. `--on maintainer` needs neither. Anything else is refused with a pointer to this
section. The body names a dependency in any of these places:

| Form | Example | Counts |
| --- | --- | --- |
| The `### Blocked by` section of the issue form (`.github/ISSUE_TEMPLATE/task.yml`) | `#631 (the greybox), and the formula page's pull request (#622).` | every `#N` in the section, up to the next heading |
| A `Starts after` line | `Starts after #630 merges (it adds smallmap_kit.py).` | the `#N` before the first parenthesis, semicolon or end of the sentence |
| A `Depends on:` line | `Depends on: #53 to #57, Ryubara/gdstudio#12` | every reference on the line; `#53 to #57` counts each number |
| A `Carried from` line | `Carried from #228 (PR #597, ...)` | the issue, not the pull request after it |

A `#N` anywhere else (the summary, the steps, a later section) is a mention, not a dependency, and is refused.

```text
uv run --project <workspace>/repos/gdstudio/python gds issue block Ryubara/deadnight#568 --on "#227" --why "needs the bot rig #227 adds"
uv run --project <workspace>/repos/gdstudio/python gds issue block Ryubara/deadnight#231 --on "#230" --why "both rewrite the shop table" --conflict src/shop/shop_table.gd
uv run --project <workspace>/repos/gdstudio/python gds issue block Ryubara/deadnight#52 --on maintainer --why "a person must launch the Activity"
```

The first needs #227 in one of the forms above (say `Depends on: #227.`) in #568's body, the second names the files,
the third needs nothing. Each sets `S-blocked` and writes `Blocked (coordinator, <date>): waits on #230: <why>` in the
issue body (with `(conflict in: <files>)` after the reason for the second). `gds issue list` prints the reason class
beside each block: `[dependency]`, `[conflict]`, `[maintainer]`, or `[none named]` for a block written by hand that
its issue body does not back, so a chain of blocks on one running issue shows at a glance. A blocked issue leaves
the line, so it stops holding a slot of the window; when what it waits on closes, `gds issue list` shows it under
"Unblocked: label to remove" and `gds issue unblock <ref>` puts it back. The coordinator's `Stop` is refused while an
issue in "May start now" has no agent and no reason ([Hooks: idle issues](hooks.md#idle)).

## Starting an issue

```text
uv run --project <workspace>/repos/gdstudio/python gds issue start Ryubara/deadnight#523 --agent godot-engineer-4
```

If `#523` is not among the first five ready issues, nothing changes and the command prints why and lists the issues
that may start instead. Otherwise it makes the branch and worktree ([below](#worktree)), sets `S-in-progress`, removes
`S-ready-to-start` and `S-needs-triage`, assigns the issue to the GitHub user running it and records the start in
`<workspace>/cache/issues-started.json` (issue, agent, time, branch, worktree). It posts no comment: the labels say
that work is under way ([Hooks](hooks.md#comments)). It ends with the lines to paste into the agent's prompt:

```text
Worktree: C:/Repositories/GDStudio/worktrees/deadnight/net-add-the-lobby-list
Issue: Ryubara/deadnight#523
```

A request that arrives while older issues wait is filed as an issue (`gh issue create`); it joins the end of the
line and starts when its turn comes, or when the maintainer marks it `P-critical`.

## Pausing a game {#paused}

The maintainer pauses a repository when other work goes first (Deadnight was paused on 2026-11-07 so the kit work
comes first). The pause lives in the kit's `workspace.toml`, on the repository's entry, with the reason and the date:

```toml
[repos.deadnight]
url = "https://github.com/Ryubara/deadnight.git"
role = "game"
paused = "by the maintainer on 2026-11-07, for kit work first"
```

Only the maintainer sets or removes `paused`; an agent that thinks a pause should end says so in its report. While it
is set, everything that offers work skips the repository's issues unless they carry `P-critical` (which only the
maintainer sets):

- `gds issue start` refuses the start, nothing changes, and the message gives the reason.
- `gds issue list` prints `PAUSED: <reason>` at the top, offers only `P-critical` issues under "May start now" and
  shows the rest as "Held by the pause".
- The coordinator's `Stop` hook ([Hooks: idle issues](hooks.md#idle)) lists none of its issues, not even blocked ones
  whose blocker has closed.

What still runs: scheduled CI and the nightlies keep running and keep their issues current. Pull requests already
open stay open, and no agent merges one while the repository is paused. A pause kept only in someone's memory or in
a plan's wording does not count, because no tool can read it
([lesson](../lessons/2026-11-07-a-pause-kept-in-memory-lost-to-the-hook-that-offers-work.md)).

## The branch and worktree {#worktree}

An agent never makes its own branch. A mistake in a hand-made branch or merge is found after the push, where fixing it
takes a force push (the maintainer's) or a new pull request ([lesson](../lessons/2026-11-02-a-local-check-judged-the-draft-and-ci-the-stored-commit.md)).
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
3. records the worktree in the ledger and prints `Worktree: <absolute path>` for the prompt.

If the worktree cannot be made, or a hook stays missing, the issue is left as it was and the worktree and branch it
made are removed; if GitHub fails after the worktree exists, it is removed too. `--no-worktree` skips the step for an
issue that needs no code. For a `PR:` task the agent adds a worktree of the pull request's branch itself, with an
absolute path (`git -C <workspace>/repos/<repo> worktree add <workspace>/worktrees/<repo>/<branch> <branch>`): a
relative path with `git -C` resolves inside the repository.

### The worktree is removed when the work is finished {#sweep}

Nobody removes a worktree by hand: `gds worktree sweep` does it once the pull request merged or the issue closed (and
for detached reviewer and probe worktrees after hours without a touch), keeping loose artwork, notes and probes in
`scratch/<repo>/<branch>/kept/` ([the rules](workspace.md#sweep)). It never removes a worktree a process uses, one with
commits on no remote branch, or one touched in the last half hour. Work that must outlive the worktree is committed or
written to `scratch/`.

### A takeover reuses the worktree {#takeover}

When an agent stalls and another takes the issue (`gds issue release <ref>`, then `gds issue start <ref> --agent <new>`),
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

An issue with an open pull request has no such takeover: `start` refuses it, and `release` leaves it in progress, because
the pull request still closes it. Skip both. Give the new agent `PR: <owner/repo>#N` and the `Worktree:` line of the old
one, whose folder is the pull request's branch.

## Starting an agent

The prompt of every task agent (`godot-engineer`, `backend-engineer`, `blender-artist`, `level-designer`, any agent
that is not a read-only helper or the reviewer) has a line of one of these forms:

| Line | For | The hook checks |
| --- | --- | --- |
| `Issue: <owner/repo>#N` | new work | the issue is in the ledger of `gds issue start` |
| `PR: <owner/repo>#N` | work on an existing open pull request: a review, a red check (a broken `main` has its pull request or issue), a conflict (DIRTY), review comments | GitHub says the pull request is open |

Both lines can appear; each must hold. An agent whose prompt has neither is refused with how to start the issue.

`gds issue start` also maps the issue's labels to areas of the
mistakes glossary (`gds lessons <area>`) (built from the lessons; `docs/lessons/areas.toml`) and keeps them in
the ledger: the checks of those areas are put into the agent's context when it starts
([Hooks: docs](hooks.md#docs)). `gds lessons <area>` prints them for a person.

## Looking

```text
gds issue list [owner/repo]
```

prints the window (what may start now, and how many issues wait behind it), the issues in progress with their owner
(the agent from the ledger, else the assignee) and the pull request that carries each, the blocked issues with the
reason each gives (one blocked with no `Blocked (...)` line says so), the **unblocked** ones (blocked, but every issue
they waited on has closed: lift them with `gds issue unblock`), and the issues waiting for information. An issue in
progress with **no owner** (no ledger entry, no assignee, no pull request) is called out: someone set the label by hand
or the agent was moved off it; give it an owner or release it. Any open
pull request carrying `S-in-progress` is listed too, so the label can be taken off.

## Stopping and finishing

- `gds issue release <ref> [--agent name]`: work stopped. The issue goes back to `S-ready-to-start`, unassigned, out of
  the ledger, with a comment. An open pull request that still closes it keeps it in progress, and the command says so.
- `gds issue block <ref> --on <#N|maintainer> --why "<text>" [--conflict <path>...]` and `gds issue unblock <ref>`:
  take an issue out of the line with its reason, and put it back ([above](#parallel)). `--on` must be another open
  issue or pull request of the repository (or `owner/repo#N`) that the issue's body names as a dependency, unless
  `--conflict` names the files; an issue in progress is released first.
- `gds issue done <ref>`: clears the ledger entry. It is rarely needed: merging a pull request with `Fixes #N` closes
  the issue, and the next `gds issue start` or `gds issue list` drops the ledger entries of closed issues.

## Landing pull requests {#landing}

Open pull requests come before new work: each one left open goes stale against `main` and makes the next harder.

- **Land, then start.** Each time the queue is read, a red `main` is fixed first, then every conflicting or failing
  pull request gets an owner, oldest first, before new feature work starts. On 2026-11-01 pull requests stacked up red
  and conflicting for hours while new ones kept landing, and each merge made the old ones worse; on 2026-11-02, 21 were
  open with 33 jobs queued.
- **Land what you would recommend.** A pull request the coordinator would recommend is refreshed and landed, and its
  trade-off reported afterwards, so the maintainer can reverse it. It is not parked behind "merge? recommended". Only
  `S-hold` ([Hooks: the hold](hooks.md#hold)), a maintainer decision of `AGENTS.md`, or having no recommendation waits
  for the maintainer.
- **Refresh a parked pull request.** One whose last run is older than recent merges to `main` gets `main` merged in and
  its checks rerun before it lands, even when GitHub says CLEAN: CLEAN only says the text merges and the last checks
  passed. Several land one at a time. On 2026-11-06 three parked pull requests landed unrefreshed and `main` went red: a
  shorter reload met a test added after its last run.
- **Hand-merge paths** (`AGENTS.md`: conventions, `AGENTS.md`, settings, hooks, `tools.toml`) are merged by hand, never
  by auto-merge, by the maintainer or by an agent the maintainer has authorized for it.

## Merging main into a pull request

Merge `origin/main` into the branch only when the pull request is DIRTY or `main` broke one of its checks: every push
restarts its CI. A pull request parked for a while is refreshed before it lands ([above](#landing)). Test the merge
locally first, and push once. The merge commit's message is checked like any other: it
ends with the single `Co-Authored-By` trailer and nothing after it. `gds merge-main` makes that commit:

```bash
uv run --project <workspace>/repos/gdstudio/python gds merge-main     # in the worktree
# conflicts: it stops, lists the files and leaves the merge in progress; fix them, git add each, then
uv run --project <workspace>/repos/gdstudio/python gds merge-main --continue
```

It fetches `origin/main`, merges with `--no-commit`, and commits with the whole message from a file
(`git commit --cleanup=strip -F`): `Merge origin/main into <branch>`, a blank line, and the `Co-Authored-By` line of the
branch's newest commit (`--co-author "<model> <noreply address>"` names another). It refuses a dirty tree and a branch
that already has `main`. Never `git merge -m ...` and `git commit --no-edit` a merge that had conflicts: git adds a
`# Conflicts:` paragraph after the message, which pushes the trailer out of the last paragraph and fails `pr-rules`
([lesson](../lessons/2026-11-02-a-merge-committed-after-conflicts-lost-its-trailer.md)). The `pre-push` hook now stops
such a commit before it leaves the machine ([Hooks](hooks.md#pre-push)); reword it with
`git commit --amend --cleanup=strip -F <message file>`. A commit that is already pushed cannot be reworded without a
force push, which is the maintainer's decision: open the same change from a new branch instead.

## Why a tool and a hook

The rule used to live in the coordinator's memory and was broken the day a new request arrived while older issues
waited ([lesson](../lessons/2026-11-02-a-rule-in-memory-is-broken-under-pressure.md)). Now the order is a function of the
issue list, not of anyone's attention: the tool computes it, the ledger records it, the hook refuses an agent that skips
it.
