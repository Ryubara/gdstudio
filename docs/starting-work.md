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

## Starting an issue

```text
uv run --project <workspace>/repos/gdstudio/python gds issue start Ryubara/deadnight#523 --agent godot-engineer-4
```

If `#523` is not among the first five ready issues, nothing changes and the command prints why and lists the issues
that may start instead. Otherwise it makes the branch and worktree ([below](#worktree)), sets `S-in-progress`, removes
`S-ready-to-start` and `S-needs-triage`, assigns the issue to the GitHub user running it, comments "Started by agent
godot-engineer-4" and records the start in `<workspace>/cache/issues-started.json` (issue, agent, time, branch,
worktree). It ends with the lines to paste into the agent's prompt:

```text
Worktree: C:/Repositories/GDStudio/worktrees/deadnight/net-add-the-lobby-list
Issue: Ryubara/deadnight#523
```

A request that arrives while older issues wait is filed as an issue (`gh issue create`); it joins the end of the
line and starts when its turn comes, or when the maintainer marks it `P-critical`.

## The branch and worktree {#worktree}

An agent never makes its own branch. A mistake in a hand-made branch or merge is found after the push, where fixing it
takes a force push (the maintainer's) or a new pull request ([lesson](lessons/2026-11-02-a-local-check-judged-the-draft-and-ci-the-stored-commit.md)).
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

## Starting an agent

The prompt of every task agent (`godot-engineer`, `backend-engineer`, `blender-artist`, any agent that is not a
read-only helper or the reviewer) has a line of one of these forms:

| Line | For | The hook checks |
| --- | --- | --- |
| `Issue: <owner/repo>#N` | new work | the issue is in the ledger of `gds issue start` |
| `PR: <owner/repo>#N` | work on an existing open pull request: a review, a red check (a broken `main` has its pull request or issue), a conflict (DIRTY), review comments | GitHub says the pull request is open |

Both lines can appear; each must hold. An agent whose prompt has neither is refused with how to start the issue.

`gds issue start` also maps the issue's labels to areas of the
[mistakes glossary](research/mistakes-by-area.md) (built from the lessons; `docs/lessons/areas.toml`) and keeps them in
the ledger: the checks of those areas are put into the agent's context when it starts
([Hooks: docs](hooks.md#docs)). `gds lessons <area>` prints them for a person.

## Looking

```text
gds issue list [owner/repo]
```

prints the window (what may start now, and how many issues wait behind it), the issues in progress with their owner
(the agent from the ledger, else the assignee) and the pull request that carries each, the blocked issues, and the
issues waiting for information. An issue in progress with **no owner** (no ledger entry, no assignee, no pull request)
is called out: someone set the label by hand or the agent was moved off it; give it an owner or release it. Any open
pull request carrying `S-in-progress` is listed too, so the label can be taken off.

## Stopping and finishing

- `gds issue release <ref> [--agent name]`: work stopped. The issue goes back to `S-ready-to-start`, unassigned, out of
  the ledger, with a comment. An open pull request that still closes it keeps it in progress, and the command says so.
- `gds issue done <ref>`: clears the ledger entry. It is rarely needed: merging a pull request with `Fixes #N` closes
  the issue, and the next `gds issue start` or `gds issue list` drops the ledger entries of closed issues.

## Merging main into a pull request

Merge `origin/main` into the branch only when the pull request is DIRTY or `main` broke one of its checks: every push
restarts its CI. Test the merge locally first, and push once. The merge commit's message is checked like any other: it
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
([lesson](lessons/2026-11-02-a-merge-committed-after-conflicts-lost-its-trailer.md)). The `pre-push` hook now stops
such a commit before it leaves the machine ([Hooks](hooks.md#pre-push)); reword it with
`git commit --amend --cleanup=strip -F <message file>`. A commit that is already pushed cannot be reworded without a
force push, which is the maintainer's decision: open the same change from a new branch instead.

## Why a tool and a hook

The rule used to live in the coordinator's memory and was broken the day a new request arrived while older issues
waited ([lesson](lessons/2026-11-02-a-rule-in-memory-is-broken-under-pressure.md)). Now the order is a function of the
issue list, not of anyone's attention: the tool computes it, the ledger records it, the hook refuses an agent that skips
it.
