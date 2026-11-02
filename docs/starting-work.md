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
that may start instead. Otherwise it sets `S-in-progress`, removes `S-ready-to-start` and `S-needs-triage`, assigns
the issue to the GitHub user running it, comments "Started by agent godot-engineer-4" and records the start in
`<workspace>/cache/issues-started.json` (issue, agent, time, branch; `--branch` when it is known). It ends with the line
to paste into the agent's prompt:

```text
Issue: Ryubara/deadnight#523
```

A request that arrives while older issues wait is filed as an issue (`gh issue create`); it joins the end of the
line and starts when its turn comes, or when the maintainer marks it `P-critical`.

## Starting an agent

The prompt of every task agent (`godot-engineer`, `backend-engineer`, `blender-artist`, any agent that is not a
read-only helper or the reviewer) has a line of one of these forms:

| Line | For | The hook checks |
| --- | --- | --- |
| `Issue: <owner/repo>#N` | new work | the issue is in the ledger of `gds issue start` |
| `PR: <owner/repo>#N` | work on an existing open pull request: a review, a red check (a broken `main` has its pull request or issue), a conflict (DIRTY), review comments | GitHub says the pull request is open |

Both lines can appear; each must hold. An agent whose prompt has neither is refused with how to start the issue.

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
restarts its CI. Test the merge locally first, and push once. The merge commit's message is checked like any other:
it ends with the single `Co-Authored-By` trailer and nothing after it.

```bash
git merge origin/main            # fix any conflicts, then git add them
git commit --cleanup=strip -F message.txt   # message.txt ends with the one Co-Authored-By line
git log -1 --format=%B           # the trailer is the last line, with no "# Conflicts:" paragraph
```

Never `git commit --no-edit` a merge that had conflicts: git adds a `# Conflicts:` paragraph after the message, which
pushes the trailer out of the last paragraph and fails `pr-rules`
([lesson](lessons/2026-11-02-a-merge-committed-after-conflicts-lost-its-trailer.md)). A pushed commit cannot be
reworded without a force push, which is the maintainer's decision: open the same change from a new branch instead.

## Why a tool and a hook

The rule used to live in the coordinator's memory and was broken the day a new request arrived while older issues
waited ([lesson](lessons/2026-11-02-a-rule-in-memory-is-broken-under-pressure.md)). Now the order is a function of the
issue list, not of anyone's attention: the tool computes it, the ledger records it, the hook refuses an agent that skips
it.
