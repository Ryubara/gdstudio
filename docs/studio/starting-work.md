# Starting work

Issues are worked from oldest to newest, at all times, and every start goes through one tool. Nobody sets
`S-in-progress` by hand and no agent starts on a request that has no started issue. The hooks enforce it
([Hooks: issue order](hooks.md#issues)).

## The rule {#the-rule}

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

- **Approach:** Start work only through `gds issue start <owner/repo>#N --agent <name>`, which refuses an issue outside
  the window of oldest ready ones (`P-critical` first); a task agent's prompt names `Issue:` or `PR:`, and a pull
  request counts as in progress by existing. **Watch out for:** a brand-new request (the outline shader, Deadnight #523)
  went to an agent the moment it arrived while older issues waited; the order lived only in memory and the status label
  was set by hand, so nothing refused it. **Seen:** gdstudio #97, 2026-11-02 (fix: the tool and its hook
  (gdstudio #97)).

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
files in each agent's prompt.

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

- **Approach:** Start every issue in each window that nothing blocks, check each running agent's newest file time on
  every monitor expiry (an hour unchanged is a stall), and report what each agent is on; a rule that says always gets a
  check that reads the state. **Watch out for:** the coordinator kept two or three agents on long issues while four kit
  issues sat startable and three agents stalled for hours unseen, and ten waiting issues without `S-blocked` held the
  window. **Seen:** GDStudio coordinator, 2026-11-02; gdstudio #165, 2026-11-02 (fix: the coordinator's `Stop` is
  refused while an issue may start with no agent ([hooks](hooks.md#idle))).
- **Approach:** Block one issue on another only for a dependency its `Depends on:` line names or for files both would
  edit; a shared subsystem is not a conflict, so start the issue and have each agent merge `origin/main` before it
  pushes. **Watch out for:** four bot issues were blocked on one running issue as the same bot brain though none needed
  what it made, and the kit's own example of a block taught that reason; one agent tuned numbers while three issues
  could run. **Seen:** GDStudio coordinator, 2026-11-02 (fix: `gds issue block` takes a named dependency or `--conflict`
  files (gdstudio #218)).

- **Approach:** Before building the core of a system, run `gh pr list` and search the open and in-progress issues for
  its words; if another branch builds it, build only the part that sits on top, against its interface, or wait for it to
  merge. The coordinator never gives two issues that need one mechanic to two agents: one owns it, the other waits
  (`Waiting on #N`), and each brief names the open pull requests and files to stay out of. **Watch out for:** the revive
  branch and the bots pull request each built a revive channel (hold, reach, prompt, events) in `game_rules.gd`,
  `player_health.gd` and `night_server.gd`; it showed when the second was ready, the merge conflicted in eight files,
  and one branch's whole channel was thrown away. **Seen:** Deadnight #486 and #511, 2026-11-02 (fix: the older pull
  request landed first and the other rebuilt on it).
- **Approach:** When pull requests touch one seam, name the other in Issues affected and merge `origin/main` before the
  last push; two halves that merge together get an integration pull request with a test of the join. **Watch out for:**
  the first playable night and a doors fix merged seconds apart with every check green, yet the night rebuilt its
  navigation its own way and the new door classes had no caller; each was tested against a `main` that lacked the other.
  **Seen:** Deadnight, 2026-11-01 (fix: the night wired to the new classes, its copy deleted, and tests of a night that
  buys a door and one that ends during the rebake).

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
a plan's wording does not count, because no tool can read it.

- **Approach:** Before starting an issue, check that its repository is not paused, and move a standing rule that lives
  only in memory into a file a tool enforces, in the same session. **Watch out for:** the pause lived in the
  coordinator's memory and the plan's wording, so the `Stop` hook and `gds issue list` offered Deadnight #1372 as ready
  and the coordinator followed the tool. **Seen:** gdstudio #786, 2026-11-07 (fix: `paused` in `workspace.toml`,
  honoured by `gds issue start`, `gds issue list` and the `Stop` hook (gdstudio #786)).

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
3. records the worktree in the ledger and prints `Worktree: <absolute path>` for the prompt.

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

## Starting an agent {#starting-an-agent}

The prompt of every task agent (`godot-engineer`, `backend-engineer`, `blender-artist`, `level-designer`, any agent
that is not a read-only helper or the reviewer) has a line of one of these forms:

| Line | For | The hook checks |
| --- | --- | --- |
| `Issue: <owner/repo>#N` | new work | the issue is in the ledger of `gds issue start` |
| `PR: <owner/repo>#N` | work on an existing open pull request: a review, a red check (a broken `main` has its pull request or issue), a conflict (DIRTY), review comments | GitHub says the pull request is open |
| `Read: <page>.md#<anchor>, ...` | the sections of the docs the agent reads before it starts | at least one, and each exists in the kit's `docs/` |

`Issue:` or `PR:` (both can appear; each must hold) and at least one `Read:` line. An agent whose prompt lacks either is
refused, with the command that fixes it.

**Before every Agent call the coordinator runs `gds brief`** for the issue or pull request the agent takes:

```text
uv run --project <workspace>/repos/gdstudio/python gds brief <owner/repo>#N [--why] [--limit 6]
```

It prints `Read: <page>.md#<anchor>` lines (the page under the kit's `docs/`), at most six, best first:

1. every section the issue names as `page.md#anchor`;
2. for each path the issue names (and a pull request's changed files): a docs page gives its section closest to the
   issue's words, any other path the closest section that mentions it (`.claude/hooks/guards.py` finds the hooks
   pages);
3. the rest by the issue's words: its title, its area labels with their descriptions (`A-agents`, "Agents and their
   instructions"), then its body, which counts least.

`--why` adds each section's title and why it is there. The coordinator copies the lines into the prompt as they are,
adds a section the task needs that the brief missed (`gds learn <words>` finds one), and drops one that does not fit.
`gds issue start` prints the same lines after `Issue:`, so a new start needs no second command; a `PR:` agent, a
resumed issue or a second agent on one issue gets its own `gds brief`. The ranking is plain word matching
(`lessons.propose`), so a brief is a proposal: the coordinator owns the final list.

There are no lesson categories: nothing maps a label to a list of rules, and the start hook injects nothing. The
sections an agent reads are named in its prompt, where the coordinator can see and change them, and the hook checks
they exist.

- **Approach:** Name the sections a task agent reads in its prompt, chosen for that issue when it is dispatched
  (`gds brief`, then the coordinator's own judgement), and refuse a prompt that names none or one that does not exist.
  **Watch out for:** the start hook could not see the prompt, so it matched agents to issues by a ten-minute note and
  injected the newest items of each label's area, the same list for every task in an area and nothing the coordinator
  could check or change. **Seen:** gdstudio #771, 2026-11-07 (fix: `gds brief`, the `Read:` guard on the Agent tool, the
  injection and its note removed, and `docs/lessons/areas.toml` with them).

## The report {#the-report}

<!-- new section: the agent definitions held the report's parts; nothing for the coordinator said what comes back -->

A task agent's final report, besides its pull request and its `Mistakes` section, says what it read:

```text
Read: studio/hooks.md#docs, studio/starting-work.md#starting-an-agent
Docs gaps: studio/hooks.md#docs: does not say what a game's hooks read; a section on briefs for games belongs on
studio/starting-work.md
```

- `Read:` names the sections it read, as `page.md#anchor` (the prompt's, and any it found with `gds learn`).
- `Docs gaps:` names each section that was missing, wrong or out of date for the task, with what, or the page a
  missing section belongs on; `Docs gaps: none` when there was nothing.

SubagentStop holds back once a task agent's report that names a pull request without both lines
([Hooks: docs](hooks.md#docs)). The coordinator reads them: a gap the agent did not fix itself becomes a docs change or
an issue, and a section that was read and did not help is one to leave out of the next brief. A pull request that
closes an issue names the same sections on its `Read first:` line.

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

## Stopping and finishing {#stopping-and-finishing}

- `gds issue release <ref> [--agent name]`: work stopped. The issue goes back to `S-ready-to-start`, unassigned, out of
  the ledger, with a comment. An open pull request that still closes it keeps it in progress, and the command says so.
- `gds issue block <ref> --on <#N|maintainer> --why "<text>" [--conflict <path>...]` and `gds issue unblock <ref>`:
  take an issue out of the line with its reason, and put it back ([above](#parallel)). `--on` must be another open
  issue or pull request of the repository (or `owner/repo#N`) that the issue's body names as a dependency, unless
  `--conflict` names the files; an issue in progress is released first.
- `gds issue done <ref>`: clears the ledger entry. It is rarely needed: merging a pull request with `Fixes #N` closes
  the issue, and the next `gds issue start` or `gds issue list` drops the ledger entries of closed issues.

- **Approach:** Prove a reported fix on the reported platform, in the build the maintainer plays, before its issue
  closes, never as a split-off follow-up: the pull request names the live web build's commit (Railway `meta.cliMessage`
  = `main <sha7>`) and runs the browser probe against the live URL after the deploy; until then say "merged, not yet
  deployed". **Watch out for:** fixes verified in tests were judged on a build behind the merge (CI queued, the deploy
  lagging, nobody noting the live commit), and a web measure split into a follow-up was never started. **Seen:**
  Deadnight #344, #353, 2026-11-01; Deadnight #464, #478, 2026-11-02 (fix: the live commit and the probe against the
  live URL in the pull request
  ([lesson](../lessons/2026-11-02-a-shared-aim-weight-coupled-hip-fire-to-the-aim-zoom.md))).
- **Approach:** Before closing an issue, grep the code for its number and resolve every "until #N" note in the same pull
  request; two buttons with different labels do different things, with a test for each route. **Watch out for:** a
  stopgap sent Quick join to the Play together screen until the rooms flow replaced it; that issue closed and the route
  stayed, so Quick join was a second Play together. **Seen:** Deadnight #526, 2026-11-02 (fix: quick join joins the
  first game found).
- **Approach:** Before opening a pull request, run the whole suite folder of every file it changes, not only the test it
  aims at. **Watch out for:** a balance fix ran only the gate test; four simulator tests around the code it changed
  failed in CI, and `main` stayed red past the deadline. **Seen:** Deadnight, 2026-11-01 (fix: CI on the fix caught it).
- **Approach:** Give work left to a later change its own issue in the same pull request, never only a line in Issues
  affected, and test that every menu entry reaches the screen it promises. **Watch out for:** Deadnight #449 built the
  Play screen with the host's match settings and left its menu route as a one-line change with no issue; the menu rework
  routed Solo straight into a night, so Solo never offered the settings. **Seen:** Deadnight #620, 2026-11-02 (fix:
  deadnight #637 routed it and walks every menu entry
  ([lesson](../lessons/2026-11-02-a-finished-screen-was-never-routed-from-the-menu.md))).

- **Approach:** Before starting an issue, search the merged pull requests for its number (`gh pr list --state merged
  --search "#N"`); the pull request that finishes the last part of a split issue carries `Fixes #N`, and the coordinator
  closes an issue whose parts have all merged. **Watch out for:** the prize crane's rules and visuals merged as two pull
  requests with no `Fixes`, nobody closed the issue, and it was assigned as new work. **Seen:** Deadnight #258,
  2026-11-02 (fix: the agent audited `main` first and filled only the gaps).
- **Approach:** Before calling a pull request done, walk every sentence of the issue's Summary and of the design section
  it points to, one line each: built (with the test that fails without it) or not built; whatever is not built goes
  under `Not covered` in the report and the pull request and becomes an issue. Name each place the feature must show up
  (a menu card and the night report, the lobby and the scoreboard, online and solo). **Watch out for:** the `What "done"
  means` list is shorter than the Summary, so a finished poster set in the night report was built nowhere while the
  tests and captures were green; the walk also found a set told twice and a finish invisible to the solo report.
  **Seen:** Deadnight #1073 and #1164, 2026-11-04.

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

- **Approach:** Look up the owner of any pull request red for over 30 minutes and assign one at once if none is live;
  when an agent is moved to other work, hand each pull request it leaves to someone. **Watch out for:** every open pull
  request needs a live owner: #488's owner was moved to probes and the pull request dropped off the owner map, so its
  hung `godot` job sat red about 80 minutes; it was not a model-capability problem. **Seen:** Deadnight #488, 2026-11-02
  (fix: `gds issue list` shows every issue in progress with its owner and pull request and calls out the ones with none
  ([Looking](#looking))).

- **Approach:** Before opening a new pull request, fix a red `main` and check that every older open one has a live owner
  and moved in the last hour; work the queue oldest first, one pull request per agent, only on files no open one
  touches; start each status report with the old ones; rerun a known flake at the head of the queue at once (`gh run
  rerun <id> --failed`) and file it. **Watch out for:** parallel pull requests touched the same files, a flaky check
  stalled `main`, and a pull request in work looks abandoned from GitHub, so Deadnight #402 sat four hours on a flake.
  **Seen:** Deadnight, 2026-11-01; Deadnight #402, 2026-11-02 (fix: `S-conflict` and `S-ci-failing` kept in sync
  (kit #76)).
- **Approach:** Rerun the balance gate on `main` after each merge that touches tuning, and let one balance owner rebase
  on the others. **Watch out for:** two pull requests each passed the gate alone (#260 changed speeds, #271 the crane
  price) and broke it once both were on `main`. **Seen:** Deadnight #260 and #271, 2026-11-01 (fix: the gate on the next
  pull request caught it).
- **Approach:** Land a fix several pull requests need once and have the rest merge `main`; parallel agents add their own
  rows to shared docs tables and never reword others', and the coordinator names the shared files in each prompt.
  **Watch out for:** five parallel art pull requests added rows to the same two docs and three rewrote one test with the
  same fix; auto-merge lands the first green pull request, not the oldest, so merge order only picks who settles a
  clash. **Seen:** Deadnight #655, #656, #660 and #661, 2026-11-03 (fix: the rule above).
- **Approach:** Before asking whether to merge, check the maintainer decisions list and `S-hold`; if neither applies and
  you would recommend the pull request, refresh it, land it, and report the trade-off afterwards. **Watch out for:** the
  coordinator had decided, then parked green pull requests for a yes though merging is not a maintainer decision, and
  each handoff carried the parked state on. **Seen:** Deadnight #1199, #1244 and #1252, 2026-11-06 (fix: land what you
  would recommend, above).

- **Approach:** Before pushing a follow-up commit to a branch that has a pull request, run `gh pr view <branch> --json
  state -q .state`; when it is `MERGED`, branch from `origin/main`, cherry-pick the commit and open a new pull request,
  and put every doc a task needs into the first pull request before turning auto-merge on. **Watch out for:** on a green
  docs pull request `--auto` merges within a minute, so a later push goes to a branch whose pull request is closed; the
  Stop gate looks for kit branches with commits and no pull request, and this one had one. **Seen:** gdstudio #175
  and #176, 2026-11-02; gdstudio, 2026-11-05 (fix: a new branch and pull request each time; the hooks name a branch that
  holds commits `main` lacks).
- **Approach:** Turn auto-merge on only after the proof is read: when the test plan is a long run, every job of that run
  (`gh run view <id> --json jobs`, none queued or in progress, each conclusion explained, named in the body), and turn
  it off in the same step as asking for changes. **Watch out for:** on a green, clean pull request `--auto` merges at
  once, so the step is a merge, not a setting: a pull request the maintainer meant to see first merged past its hold, a
  nightly fix merged before its dispatch finished a job that failed on a limit it had called harmless, and a pull
  request with stale numbers landed before the three fixes asked for. **Seen:** Deadnight #1115, 2026-11-04 (fix: the
  hold is a label and a required check, [Hooks](hooks.md#hold)); Deadnight #1324, 2026-11-06; Deadnight #1084,
  2026-11-04.

## Merging main into a pull request {#merging-main-into-a-pull-request}

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
`# Conflicts:` paragraph after the message, which pushes the trailer out of the last paragraph and fails `pr-rules`. The
`pre-push` hook now stops
such a commit before it leaves the machine ([Hooks](hooks.md#pre-push)); reword it with
`git commit --amend --cleanup=strip -F <message file>`. A commit that is already pushed cannot be reworded without a
force push, which is the maintainer's decision: open the same change from a new branch instead.

- **Approach:** Push only when a merge needs it (DIRTY, or `main` broke a check) and merge `main` locally for tests;
  read `gh run list --status queued` and the open count each cycle, and when the queue grows stop new pull requests,
  land the oldest, and land a flake's fix first. **Watch out for:** with many agents CI is the bottleneck: with 21 open,
  20 jobs running and 33 queued, every push restarted a 15-minute run and about ten workflows. **Seen:** Deadnight #447,
  2026-11-02 (fix: the rule above).
- **Approach:** After a conflicted merge, read the diff of every test file against `main` before rerunning the suites.
  **Watch out for:** a merge of `main` doubled a step in a test, so the branch failed for a reason the change never had.
  **Seen:** Deadnight, 2026-11-01 (fix: the night suite caught it after the merge).

- **Approach:** Commit a merge of `main` the moment its conflicts are resolved, with the whole message from a file and
  nothing after the trailer, through `gds merge-main`; run `uvx pre-commit run --files <resolved files>` before
  `--continue`, run `--continue` unpiped, and check that `git log -1` shows the merge before rebuilding or pushing.
  **Watch out for:** a hand-written title (`ui: Merge main into x`) is refused because `Merge` is not on the verb list,
  so the merge stayed open; `--continue` commits through pre-commit and a licence line of 155 characters met the 120
  limit there; a merge left staged for hours (248 files, `MERGE_HEAD` set) first met `gdlint` at commit time, when
  `main`'s growth had put a file at 1,016 lines. **Seen:** Deadnight #539, 2026-11-02; Deadnight #656 and #410,
  2026-11-02.
- **Approach:** Never push a merge of another open pull request's branch: build the parts that do not need it and merge
  after it lands. If you must build on it, keep your own work as a patch of your commits (`git diff <that branch's tip>
  HEAD > mine.patch`, saved outside the worktree), `git reset --hard origin/main` on the unpushed branch and `git apply
  --3way mine.patch`; a pull request stacked on a hand-merged sync one takes its own side of the synced files, runs `gds
  sync <game>` and `gds sync --check`, and says what it is stacked on. **Watch out for:** a squash merge writes a commit
  no branch contains, so 17 files conflicted with none of the agent's own lines, and `.claude/gds-sync.json` and
  `groundwork.py` conflicted on identical content. **Seen:** Deadnight #230 on #643, 2026-11-03; Deadnight #575 on #571,
  2026-11-02.
- **Approach:** After every `gds merge-main`, diff the branch against `origin/main` for each file it shares with a
  merged pull request (`git diff origin/main -- <file>`), delete the branch's own copy of a fix `main` landed, and drop
  a workaround whose blocking issue has closed. **Watch out for:** a clean textual merge hid a second copy: a stub
  `has_voice` and a `near_only` grip option stayed beside the real female voices and the same far-hand fix that `main`
  had landed. **Seen:** Deadnight #678, 2026-11-03 (fix: the branch wired to `main`'s mechanism, the workaround and its
  test dropped).

## Why a tool and a hook

The rule used to live in the coordinator's memory and was broken the day a new request arrived while older issues
waited. Now the order is a function of the issue list, not of anyone's attention: the tool computes it, the ledger
records it, the hook refuses an agent that skips
it.
