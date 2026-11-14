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

**The landing freeze.** Running everything stops while the kit has a queue. While more kit pull requests are open
than `merge.queue_cap` in `.github/conventions.yml` (0: any open one), no issue starts in any repository and no pull
request opens, and every agent works on landing or closing the open ones ([Landing](landing.md#landing)). Work that
would end in a new pull request is committed on its branch and parked, with a `STATUS.md` in its scratch folder that
says where it stands and what is left; a small fix found on the way rides in the open pull request being worked on, or
waits in `scratch/kit-lessons-queue/`. Every open pull request has an owner, a live agent or the coordinator's landing script,
on a line of the follow-up list. A pull request that another supersedes is closed as soon as that is known. A change
that makes measured work stale (a body swap that every solved hand and clip stands on) lands only with the re-solves
it causes filed and queued behind it, each with an owner. While the freeze is on, the idle-issue `Stop` check demands
no starts ([Hooks: idle issues](hooks.md#idle)).

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
- **Approach:** While any kit pull request is open (`merge.queue_cap` is 0), start no issue and open no pull request;
  give every open one an owner, close a superseded one at once, and land a change that invalidates measured work only
  with its re-solves queued behind it. **Watch out for:** the idle check kept demanding starts while about 31 kit pull
  requests sat open: #1299's body swap sent some 15 hand and clip pull requests back to a re-solve, two stacks hung on
  one hard fit each, three pull requests had no owner and superseded ones stayed open. **Seen:** gdstudio, 2026-11-12
  (fix: the freeze, its cap in the conventions, and an idle check that honours it).

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

## Starting an issue {#starting-an-issue}

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

The pause covers pull requests too. While it is set, no agent works a pull request of the repository: no refresh,
no rerun, no edit, no hold and no merge, and no new pull request in it, a docs move made for kit work included.

- Open pull requests are left as they are, turned into drafts (`gh pr ready --undo`), and are out of the
  [landing queue](landing.md#landing).
- Kit work that would change a paused game waits as a note on the game's own issue, or in the kit issue's "left for
  later" list, until the pause is lifted.
- `gds merge-main` on a worktree of the repository, `gds pr hold` on one of its pull requests and `gds pr check-body`
  in one of its checkouts refuse, change nothing, and print the reason (`refuse_paused` in `gds_tools/issues.py`,
  which reads the same `paused` lookup as `gds issue start`).

What still runs: scheduled CI and the nightlies keep running and keep their issues current. A pause kept only in
someone's memory or in a plan's wording does not count, because no tool can read it.

- **Approach:** Before starting an issue, check that its repository is not paused, and move a standing rule that lives
  only in memory into a file a tool enforces, in the same session. **Watch out for:** the pause lived in the
  coordinator's memory and the plan's wording, so the `Stop` hook and `gds issue list` offered Deadnight #1372 as ready
  and the coordinator followed the tool. **Seen:** gdstudio #786, 2026-11-07 (fix: `paused` in `workspace.toml`,
  honoured by `gds issue start`, `gds issue list` and the `Stop` hook (gdstudio #786)).
- **Approach:** Before refreshing, rerunning, editing or merging a pull request, or opening one for kit work, check
  that its repository is not paused; in a paused one, turn open pull requests into drafts and leave kit changes to
  it as a note. **Watch out for:** the pause covered only issues, and the landing rules read an open pull request as
  work to finish, so the coordinator refreshed and reran Deadnight #1371 and a kit task opened Deadnight #1374 during
  the pause. **Seen:** gdstudio #811, 2026-11-08 (fix: `gds merge-main`, `gds pr hold` and `gds pr check-body` refuse
  a paused repository with the reason; tests in `test_paused_prs.py`).

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
commits, and its `Read first:` line the sections the base's author read. `gds pr check-body` runs the CI `commits`
check on the branch's commits since `origin/main` and refuses a `Model:` line that misses one ([the body
guard](pull-requests.md#pr-body)); run it before `gh pr create`. The base's commits stay on the list after the base
lands (a squash merge makes a new commit on `main`), so the line keeps naming their models.

- **Approach:** When the base has landed as a squash, merge `main` into the stacked branch, put `main`'s whole tree
  in the merge (`git read-tree --reset -u origin/main` while the merge is open), re-apply only the branch's own
  change (`git diff <base tip> <branch tip> | git apply --3way`) and resolve what is left. **Watch out for:** a plain
  merge conflicts in every file of the base that changed before it landed (37 files, most of them the base's own
  and none of them the stacked branch's), and resolving them by hand risks keeping an old side of the base; the
  re-applied patch conflicted in 10 files, all the branch's own, and three of those `main` had since taken whole.
  **Seen:** gdstudio #1267 on #1040, 2026-11-12.
- **Approach:** While the base is still open, fetch it and merge its head into the stacked branch right after
  `main`, before resolving any docs fold or rebuilding anything solved on the base's files; where both merged the
  same `main`, take the stacked branch's code and the base's docs with the branch's own lines added. **Watch out
  for:** the base's agent works at the same time: it had merged the same `main`, rebuilt its clips on the new hold
  and folded its page into another section while the stacked branch was resolving `main` alone, so the fold made
  there (a section of its own) was redone into the base's section, and the clip that joins the base's would have
  been solved on the base's old files. **Seen:** gdstudio #1265 on #1191, 2026-11-12.
- **Approach:** Commit the merge of an open base branch with a message file that ends in the trailer (`git commit
  --cleanup=strip -F <file>`); `gds merge-main` covers only `main`. **Watch out for:** after resolving conflicts,
  `git commit --no-edit` leaves git's `# Conflicts:` list as the last paragraph, so the commit-trailers hook refused the
  merge. **Seen:** gdstudio #1436 on #1456, 2026-11-13 (twice: the second agent on the task did it again on its
  first merge of the base).

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

1. every section the issue names as `page.md#anchor`; a section a split left as a pointer gives the section it moved
   to, here and in the steps below ([page size](rules.md#size), gdstudio #1471);
2. for each path the issue names (and a pull request's changed files): a docs page gives its section closest to the
   issue's words, any other path the closest section that mentions it (`.claude/hooks/guards/` finds the hooks
   pages), when that section's words score at least a third of the best section's (a pull request's changed files
   need no such closeness);
3. the rest by the issue's words: its title, its area labels with their descriptions (`A-agents`, "Agents and their
   instructions"), then its body, which counts least.

It names only headings with an explicit `{#anchor}`, never a page's `#` title or a heading the site slugged itself:
`ai.md#ai-characters-in-3d-third-person` and `index.md#blender`, the slugs of two titles, read as missing to the
agents given them (gdstudio #1193).

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

- **Approach:** The coordinator starts an agent for an issue's work (`gds issue start`, then the brief) even when the
  maintainer asks the coordinator to redo work itself: that means the studio's own agents redo it, not the
  coordinator writing the code. **Watch out for:** the coordinator built most of a template feature itself, which
  filled its context with probe output and left the queue unattended until the maintainer asked why. **Seen:**
  gdstudio #846, 2026-11-10 (fix: the work and every finding handed to a godot-engineer with a full brief).
- **Approach:** Write the model line in a brief as the model the agent runs as (the commit trailer and the pull
  request's `Model:` line name it; the agent definition's `model:` sets it), or tell the agent to name the model the
  harness says it is. **Watch out for:** the coordinator copied its own model into briefs, but the godot-engineer runs
  another model, so an agent had to rewrite its unpushed commit messages and the others needed a correction mid-task.
  **Seen:** gdstudio #875, 2026-11-10 (fix: briefs say to name the model the agent actually runs as).
- **Approach:** Add `studio/capture.md#attaching` to the `Read:` lines of every task with something to see, and
  `studio/shell.md#scripted-edits` to every task that edits GDScript or Python by script, whatever the brief proposed.
  **Watch out for:** `gds brief` ranks by the issue's words, and a feature issue rarely names how captures are
  attached or how files are edited, so its agent met the image rules only as refusals and a failed `pr-rules`, and
  the scripted-edit section ranked ninth for #1040, past the six a brief prints. **Seen:** gdstudio #880 and #886,
  2026-11-10; gdstudio #1040, 2026-11-11.
- **Approach:** Let a path the issue names pick a section only when that section's words are also close to the
  issue's (`MENTION_FLOOR` in `lessons.py`: a third of the best section's score). **Watch out for:** an issue's `Area`
  line repeats its label's folders (`game/core/`) and many sections cite a file as an example, so the one section that
  mentions such a path was named however far its subject; #909 (online play) was briefed with the voice-lines section.
  **Seen:** gdstudio #1133, 2026-11-11 (fix: the floor, tuned on 120 kit issues; the far mentions scored 0.17 to 0.31
  of the best, the fitting ones 0.35 and up).
- **Approach:** Write a prompt's pull request instructions in the body template's own words: the issue line is
  `Fixes #N`, put near the top of the brief where an agent reads it, not deep in a list. **Watch out for:** the body
  check accepts only `Fixes #N`, and prompts that said `Closes #N` sent each agent to find out from a refusal; one
  successor still wrote `Closes` after the brief was fixed, because the line was buried. **Seen:** gdstudio #1188,
  #1183, #1184, #1189, #1190, #1192, #1193 and #970, 2026-11-11 (coordinator's mistake; the batch brief now says it).
- **Approach:** Tell an agent with captures to run `gds pr check-body <body> --attach ./<file>` from the captures
  folder, with the same `--attach` arguments as its `gh pr create` ([Attaching](capture.md#attaching)). **Watch out
  for:** before #1200 the hand check had no `--attach`, refused every local capture and sent agents to the
  `gh pr create` guard to learn the result. **Seen:** gdstudio #1188 (PR #1200), #1221, 2026-11-11.
- **Approach:** Point a prompt at another task's work by its worktree or branch (`worktrees/<repo>/<branch>/`), which
  exists from `gds issue start`, unless `gh pr list --search <N>` shows a pull request. **Watch out for:** a prompt
  said to find #1037's branch with `gh pr list`, but #1037 had no pull request yet, so the agent searched for one that
  did not exist. **Seen:** gdstudio #1221, 2026-11-11 (coordinator's mistake).

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

- **Approach:** Name a section on `Read:`, `Read first:` and `Lessons:` by its path under `docs/` in full
  (`engines/godot/ragdoll.md#limits`), never by the page alone. **Watch out for:** the kit's body check looks each
  section up from `docs/`, so `ragdoll.md#limits` is refused as a section that does not exist. **Seen:** gdstudio
  #846, 2026-11-10.
- **Approach:** List on `Read first:` and in the report's `Read:` only the sections you opened, and run `gds learn
  <words>` for more before you start; a brief's line you skipped is left out or named as skipped. **Watch out for:**
  the check sees that a section exists, not that it was read, so a body that copied all six `Read:` lines of its
  brief, one of them read, passed; it came out only after the merge, and the coordinator corrected the body. **Seen:**
  gdstudio #928 (PR #987), 2026-11-10.

## Looking {#looking}

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
  live URL in the pull request).
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
  deadnight #637 routed it and walks every menu entry).

- **Approach:** In a pull request that only works on an issue (one bucket of a split task), name the issue as "#N stays
  open" and put it under Issues affected, never in a sentence with "close" or "closes" before it. **Watch out for:** the
  CI body check reads "does not close #770" as a pull request that closes an issue, so it asked for `Read first:`
  areas, the local `gds pr check-body` passed (it has no labels) and the body check failed on the first push. **Seen:**
  gdstudio #799, 2026-11-08 (fix: the sentence was reworded and the body edited; the check passed on the next run).
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
- **Approach:** Report an open pull request's state to the maintainer only from a fresh read of it (`gh pr view` or
  `gh pr checks`), and check that the agent that owns it is still running; a pull request whose agent has stopped and
  whose checks failed is the coordinator's to fix or hand on at once. **Watch out for:** the coordinator repeated an
  agent's last word, "waiting on its checks", in several updates while #808's Windows job had failed and its agent had
  stopped, until the maintainer found the failure. **Seen:** gdstudio #797, 2026-11-08 (fix: the coordinator found the
  cause, a leaked `GDS_QUIET`, fixed it in #808 and landed it).

## Landing pull requests {#landing}

Open pull requests land before new work starts, oldest stuck one first, each refreshed against `main` before it
lands: the rules and their entries are on [Landing a pull request](landing.md#landing).

## Merging main into a pull request {#merging-main-into-a-pull-request}

Only when the pull request is DIRTY or `main` broke one of its checks, through `gds merge-main`: on
[Landing a pull request](landing.md#merging-main-into-a-pull-request).

## Why a tool and a hook {#why-a-tool-and-a-hook}

The rule used to live in the coordinator's memory and was broken the day a new request arrived while older issues
waited. Now the order is a function of the issue list, not of anyone's attention: the tool computes it, the ledger
records it, the hook refuses an agent that skips
it.
