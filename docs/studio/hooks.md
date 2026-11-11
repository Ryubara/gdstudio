# Hooks

Claude Code hooks are the rules enforced *while* an agent works, before anything reaches git or GitHub. Every event
goes to one dispatcher, `.claude/hooks/dispatch.py`; a game runs the same one through its `.claude/hooks/launch.py`,
which finds the kit by the workspace marker. Settings: `.claude/hooks/hooks.toml` (a game may override keys in
`.claude/hooks.local.toml`).

## What it refuses {#what-it-refuses}

| Guard | Refuses | Instead |
| --- | --- | --- |
| Agents | `general-purpose`, or an Agent call with no type | a project agent (`.claude/agents/`) or a read-only helper |
| Unpublished docs | an agent finishing, or a session stopping, while a branch of the kit's worktrees has commits and no pull request, or commits made after its pull request merged; an agent's report with a `Mistakes` section that names no section its kit branch updates; a task agent's report that names a pull request without a `Read:` line and a `Docs gaps:` line (held once) | push the branch and open its pull request; write the entry into its section; add the two lines ([below](#docs)) |
| Agent stalls | a task agent (`godot-engineer`, `backend-engineer`, `blender-artist`, `level-designer`) finishing on a message that is not a report: no pull request link or number, no `Mistakes` section, no `Blocked:` line, and no background task running | do the announced step in the same turn, or end with the report or `Blocked: <why>` ([below](#stall)) |
| Idle issues | the **main session** (the coordinator) ending a turn while an issue in any repository of `workspace.toml` may start now (the window's "May start now", or blocked with a blocker that has closed) and has no agent; never a task agent | start each (`gds issue start`), or take it out of the line with a reason (`gds issue block <ref> --on <#N\|maintainer> --why "..." [--conflict <path>...]`) ([below](#idle)) |
| Issue order | a task agent whose prompt names no started issue (`Issue: owner/repo#N`) or open pull request (`PR: owner/repo#N`); `gh issue edit\|create --add-label S-in-progress`; `S-in-progress` on a pull request; `P-critical` from a session | `gds issue start <ref> --agent <name>` ([Starting work](starting-work.md)) |
| Sections read first | a task agent whose prompt has no `Read: <page>.md#<anchor>` line, or names a section the kit's `docs/` does not have (`[brief] enforce`) | `gds brief <owner/repo>#N` and its lines in the prompt ([Starting an agent](starting-work.md#starting-an-agent)) |
| Disk | under `[disk] hard_gb` free (10 GB): a task agent's start, `git worktree add` (and `gds issue start`) ([below](#disk)) | `gds disk guard`; report what is left to the coordinator and the maintainer |
| Git | commits or pushes on `main`; force pushes; `--no-verify` | a branch in a worktree, a pull request |
| Merge | `gh pr merge --admin`; merging a pull request that changes a manual path | let checks pass; report it to the maintainer |
| Hold | a merge command (`gh pr merge`, with or without `--auto`, or `gh api .../pulls/<n>/merge`) on a pull request carrying `S-hold`; taking `S-hold` off (`--remove-label`, a `gh api` write, `gh label delete\|edit`); GraphQL merge and label mutations ([below](#hold)) | stop and report; only the maintainer takes a hold off |
| Behind main | a merge command (as in Hold) on a pull request whose head lacks the tip of its base, by GitHub's compare (`behind_by` > 0); an API failure only warns ([Landing](landing.md#landing)) | `gds merge-main --path <worktree>`, push, merge once the checks pass |
| Comments | any `gh` command that posts a comment or a review under the maintainer's account: the `comment` commands, `gh pr review`, `--comment` or `-c` on a close or reopen, `gh api` writes to a comments or reviews path, GraphQL mutations ([below](#comments)) | the same command without the text; the text goes in the scratch folder and the report |
| Tools | Godot or Blender from Steam or PATH | `gds tool path godot\|blender` |
| Windowed Godot | Godot started from a shell without `--headless`: its window takes the keyboard focus (docs/engines/godot/no-focus.md) | `gds godot -- <arguments>` or `gds capture frames`; `--headless` when nothing is drawn |
| Godot audio | a Godot started with a real `--audio-driver` (not `Dummy`), or `gds godot --with-audio`: it plays through the speakers of the person at the machine (docs/engines/godot/no-focus.md#sound) | drop the option: `gds godot` adds `--audio-driver Dummy`, `--headless` and Movie Maker force it |
| Browser probes | a `tools/web_smoke/*.py` script or a Playwright run (`playwright test`, `uv run --with playwright python x.py`) not wrapped in `gds quiet`: headless Chrome under pointer lock clips the person's cursor (docs/engines/godot/no-focus.md) | `gds quiet -- <command>` |
| Pull request images | `gh pr create\|edit --attach <file>` whose body file (`--body-file`, or a literal `--body`) does not refer to every attached file inside `## Screenshots` by a path that names the same file as `--attach` (`./x.png` is `<the folder the command runs in>/x.png`, [the image guard](pull-requests.md#attach-paths)), has no image between `Before:` and `After:` (unless `Before: none (reason)`) or none below `After:`, or cannot be read before the command runs (`[attach]` in `hooks.toml`) | write the body to a file with `![before](../before.png)` / `![after](../after.png)` on those lines, `cd` into the folder that holds the images, then `--body-file <file> --attach ./before.png ...`; read the body back |
| Local images left in a pull request | after a shell command that opened or edited a pull request, or printed one's address as its last line (a script, an alias): the description read back from GitHub still has a `![x](../x.png)` reference that is not an upload (`readback` in `[attach]`) | the answer names the references; fix the description at once ([the image guard](pull-requests.md#attach-paths)) |
| Pull request body | `gh pr create\|edit` with a `--body-file` (or a literal `--body`) that `groundwork.py check-body` refuses: the rules `pr-rules` runs after the push (`[pr_body]` in `hooks.toml`, [the body guard](pull-requests.md#pr-body)) | fix the body file, check it with `gds pr check-body <file> [--title <file>]`, then run the command |
| Kills | stopping Godot or Blender by name (`taskkill /IM`, `pkill`, `killall`, `Stop-Process -Name`): every agent's run dies | kill your own process by its PID |
| Secrets | printing a key-like variable; dumping the environment | test that it is set |
| Files | editing secrets, caches, git internals, pinned tools; generated files | edit the source (`conventions.yml`, then render) |

All reasons come back at once. A refusal is Claude Code's JSON answer with exit code 0; if the dispatcher itself
fails, the call is allowed and the error printed, so a broken guard never locks a session out.

The guards that read a shell line split it into simple commands (`&&`, `||`, `;`, `|`) and judge each by its program.
Before naming the program they drop the leading `NAME=value` words (a quoted value or a `$(...)` with spaces
included) and the words `&`, `.`, `call`, `exec`, `time` and `sudo`, so `GODOT="$(gds tool path godot)"` is an
assignment, never a Godot start, and `FOO=1 git push` is judged as `git push` (`segments` in
`.claude/hooks/guards/shell.py`; gdstudio #1004). A launcher (`env`, `nohup`, `timeout`, `cmd /c`, `start`,
`Start-Process`) is judged by the program it starts, and a continued line (`\` or a backtick) stays one command. A
plain `cd <dir>` is followed: the commands after it are judged in that folder.

- **Approach:** Judge each simple command by its program word, after any launcher, never by a word after it.
  **Watch out for:** a newline after `find \` made `godot -name '*.gd'` a Godot start, while `env godot` passed; a
  bare `env` is a command itself. **Seen:** gdstudio #1192, 2026-11-11.

## Pull request bodies before they are sent {#pr-body}

Moved to [Pull requests: the body guard](pull-requests.md#pr-body): `gds pr check-body`, the guard before `gh pr
create|edit` and what neither can judge. This page had reached its size limit.

## Which paths the image guard covers {#attach-paths}

Moved to [Pull requests: the image guard](pull-requests.md#attach-paths): the measured table of what `gh --attach`
rewrites, and the read-back after the command.

## Commit messages before they leave the machine {#pre-push}

The `pre-commit` framework installs three git hooks (`default_install_hook_types` in `.pre-commit-config.yaml`), and
`gds issue start` checks them ([Starting work](starting-work.md#worktree)):

| Git hook | Runs | Judges |
| --- | --- | --- |
| `pre-commit` | formatting, lint, the generated files | the staged files |
| `commit-msg` | `groundwork.py check-title --commit-msg` and `check-message` | the message file git hands over, before git's cleanup |
| `pre-push` | `groundwork.py check-push` | every commit being pushed (`PRE_COMMIT_FROM_REF..TO_REF`, minus what `origin/main` has), merges included, as stored |

One function, `commit_problems`, judges a message in all three places and in CI (`check-commits`). The only input
handling is `stored_message()`: the help text git adds in the editor (and the `--verbose` diff under the scissors line)
is not part of the commit, so it is removed; every other line counts, including `#` lines, because `-m`, `-F` and
`--no-edit` keep them. The `commit-msg` hook cannot see what git will do afterwards (a `--cleanup=strip -F` message with
`#` lines is judged as kept, the safe side), so `pre-push` is the check that matches CI. It refuses the push with the
commits and what is wrong, and the fix needs no force push because the commit is still local: `git commit --amend
--cleanup=strip -F <message file>` for the last commit, `git reset --soft <base>` and a new commit for an older one. A
branch deletion and an empty push pass. `--no-verify` is refused by the Git guard above.

- **Approach:** Choose a commit and pull request title from the verb list (Add, Fix, Update, Remove, Rebuild, Rework,
  Improve, Document), never copy an issue's title; run `gds pr check-body <body> --title <title file>` before
  committing, and read the commit's output before chaining the push and `gh pr create`. **Watch out for:** an issue title
  is not checked and "Step" (or "Keep") is no verb: the commit hook refused the commit, and the chained `gh pr create`
  then said "No commits between main and <branch>", which hid the first error (it also means a push that never
  happened: check `git status -sb`). **Seen:** Deadnight #892, 2026-11-03 (fix: retitled "Fix the two-thumbs touch
  test that waits on real frames"); gdstudio #1094, 2026-11-11 (a silent `git push -q` that never reached GitHub).

## The hold {#hold}

A pull request the maintainer must see first carries the label `S-hold`. GitHub enforces it, not this hook: the `hold`
job of `.github/workflows/hold.yml` fails while the label is on, and the `Main` ruleset requires that job, so no route
merges it. The rule is `merge.hold` in `.github/conventions.yml`. A failed `hold` is a decision, not a broken build: it
stays out of `merge.required_checks`, so `pr-status` does not label it `S-ci-failing`.

- **Set it** with `gds pr hold <owner/repo>#N`: it adds the label and returns once the check is red, because until then
  the green run before it still counts (on a real pull request: 3 s to pending, 7 to 10 s to red). Better still, open
  the pull request held: `gh pr create --label S-hold`.
- **Take it off** only on the maintainer's word, and only by hand on the pull request's page. The check re-runs with no
  new commit. Auto-merge that is on stays on through the hold, so the pull request merges the moment the label comes
  off.
- **The guard** in `guards/merges.py` gives a session the reason, and it is the only thing that stops a session taking the
  label off: every agent uses the maintainer's token, so GitHub cannot tell them apart. It reads shell commands, so it
  does not see a script that calls the API itself.
- **A pull request opened before the check was required** has no run on its head and stays pending: run
  `gh workflow run hold-sweep.yml` once. It reports the check through the Checks API and does not touch the pull
  request. A new game runs it once when its ruleset starts requiring `hold`.

Do not put an `if:` or a `paths:` filter on `hold`: a job skipped by `if:` reports success, so a filter on the label's
name would let any other label replace a failed run. `python/tests/test_hold.py` has a test for each such reason.

## Comments {#comments}

Nothing an agent runs posts a comment or a review under the maintainer's GitHub account (their decision of 2026-10-12);
status labels say that work is under way. `check_comments` in `guards/comments.py` judges what `gh` would do, because a
rule that lists the commands named `comment` let `gh issue close --comment` post on #691
([Writing checks](writing-checks.md#effects)). The routes come from every page
of `gh help` in gh 2.102 and the mutations from GitHub's schema, read on 2026-11-05; a later `gh` can add a route, so
the list is only as current as that walk.

| Route | Refused | Still allowed |
| --- | --- | --- |
| `gh issue comment`, `gh pr comment`, `gh discussion comment` | always, `--edit-last`, `--delete-last` and `--help` included | `gh help issue comment` for the manual; `gh issue view --comments` and the like |
| `gh pr review` | always, with or without text | `gh pr view`, `gh pr edit --add-reviewer` |
| `gh issue close`, `gh pr close`, `gh issue reopen`, `gh pr reopen` | `--comment`, `-c`, as `--comment=x`, `-c=x`, `-cx`, or in a cluster (`-dc x`) | the same commands without it; `--reason`, `--duplicate-of`, `--delete-branch` |
| `gh api` | `POST`, `PATCH` or `PUT` to a path with a `comments` or `reviews` part (issues, pull requests, commits, gists, discussions, teams), the method named or implied by `-f`, `-F`, `--field`, `--raw-field`, `--input` | a read of those paths, a `DELETE` of a comment, any other path |
| `gh api graphql` | `addComment`, `addDiscussionComment`, `addPullRequestReview` and its comment and thread forms, `dismissPullRequestReview`, `submitPullRequestReview`, `updateDiscussionComment`, `updateIssueComment`, `updatePullRequestReview` and its comment form; a query this guard cannot read (from a file, a variable or `--input`) | a query written in the command, any other mutation (`closeIssue`) |
| `gh alias set` | an alias whose expansion is one of the above | any other alias |

A body is not a comment: `gh issue create|edit --body`, `gh pr create|edit --body` and `gh pr merge --body` (the text of
the merge commit) are allowed. There is no exception: the claim commands of 2026-10-24 were taken out on 2026-11-06
(nothing used them), and a claim is a comment like any other.

A command counts wherever a line starts it: after `&&`, `;`, `|`, `then`, `(`, `{`, `$(...)` and backticks, behind
`env`, `timeout`, `command`, `nohup` and `xargs`, inside `bash -c`, `pwsh -Command`, `cmd /c` and `eval`, over a line
continuation, as `gh.exe` or a path to it, with `-R` before the command (`gh issue -R o/r close 5`). Text that only
mentions one passes: an `echo`, a `grep`, a commit message, a single-quoted body, a heredoc.

Not seen, because no shell line says it: a script file, a heredoc fed to a shell, `uv run gh`, `npx`, `Start-Process`,
an alias made before this guard, a `gh` extension, `curl` with a token, the website, and `gh` called from Python.
`gds` is the last of these and has its own rule, because it runs under the maintainer's account: `run_gh` in
`python/src/gds_tools/issues.py` is its one way to run `gh`, and refuses what `posts_a_comment` names; a test fails
if a second way appears. `gds issue start`, `release` and `unblock` change labels and the ledger and post nothing.
Until 2026-11-06 they did post, and this page called it by design.
Comments a workflow posts with `GITHUB_TOKEN` appear under `github-actions[bot]`, not under the maintainer.

A second copy of the rule runs on the maintainer's machine, for every project: the user-level hook
`no-comment-as-user.js`, outside this repository. It refuses any `gh issue comment` or `gh pr review` where a line
starts it, including `--help`, and reads a heredoc's lines as commands, so a test string that names one has to be
written with the Write tool. It does not know the closing routes; this guard is what covers them here.

- **Approach:** Check a rule about the maintainer's account where the effect happens (the one place a tool runs `gh`) as
  well as where an agent types, and fix a known gap that contradicts a maintainer's rule instead of listing it as a
  design or asking whether to. **Watch out for:** the no-comments rule guarded what an agent types, while `gds` posted
  its status lines from Python, where no guard reads, 595 times; the page listing the rule called that by design, and a
  handoff carried it as an open question. **Seen:** gdstudio, 2026-11-06 (fix: `gds` posts nothing and its one runner
  refuses every posting route; the comments were deleted).

## Issue order {#issues}

Issues are started oldest first, only through `gds issue start` ([Starting work](starting-work.md)). Two checks in the
dispatcher enforce it; their settings are `[issues]` in `hooks.toml` (a game replaces `window` in
`.claude/hooks.local.toml`).

**An Agent call.** The prompt of every agent that is not a helper (`[agents] helpers`, plus `[issues] exempt`, which
holds `reviewer`) needs a line that starts with `Issue: <owner/repo>#N` or `PR: <owner/repo>#N` (a list bullet or
backticks around the reference are fine; a mention in the middle of a sentence is not a line). The hook decides:

1. Not in a GDStudio workspace, or `[issues] enforce = false`: allowed.
2. A type in `[agents] refused`: that guard's reason stands alone.
3. Each `Issue:` line must be a key of the ledger `<workspace>/cache/issues-started.json`, which `gds issue start`
   wrote after it checked the window. Missing: refused, with the command to run.
4. Each `PR:` line must be an open pull request: the hook asks `gh pr view`. Merged, closed or not found: refused. If
   `gh` cannot answer (offline), the line is let through, as a guard that cannot look never locks a session out.
5. No such line at all: refused, and the reason shows both forms.

**Labels.** A shell command (`gh issue|pr edit|create`, or a `gh api` call that writes) that adds `S-in-progress` is
refused (an issue: use `gds issue start`; a pull request: it is in progress by existing and never carries the label),
and so is one that adds `P-critical` (only the maintainer sets it). Removing labels and reading are allowed.

What the hook cannot see: the window itself (that needs the network, so `gds issue start` checks it before it writes
the ledger, and the ledger is what the hook trusts); an agent that names a started issue but works on something else;
labels set through a script, the web page or `gh api --input` bodies. The next `gds issue list` shows an issue in
progress with no owner, and the weekly hygiene sweep reports labels that sit idle.

## Idle issues {#idle}

Run everything that can run in parallel, and enforce it: nothing used to notice when issues that could start sat with no
agent ([the maintainer's correction](maintainer-corrections.md); on 2026-11-02 two or three agents ran while
four kit issues waited, and later 15 Deadnight issues sat behind the window because issues that waited on #227 or on the
maintainer were not labelled `S-blocked` and held every slot). `Stop` (the main session; task agents send
`SubagentStop`, which this never touches) now refuses to end a turn while an issue is idle. Settings: `[idle]` in
`hooks.toml`.

1. **What is idle.** For every repository in the kit's `workspace.toml`, the hook computes the window with the code
   `gds issue start` uses (`gds_tools/issues.py`, loaded by path) from `gh issue list` and `gh pr list`. The issues under
   "May start now" are idle: nobody has them (no `S-in-progress`, no open pull request that closes them) and they are not
   blocked. So are blocked issues whose `Blocked (...)` line waits on issues that have all closed ("Unblocked").
   A paused repository offers only its `P-critical` issues ([Starting work: pausing](starting-work.md#paused)).
2. **The refusal** names each idle issue and gives the ways out: `gds issue start <repo>#N --agent <name>` and then an
   agent with the `Issue:`/`Worktree:` lines it prints; or `gds issue block <repo>#N --on <#N|maintainer> --why "<text>"`
   when it waits on the maintainer, or on #N that its body names (its `### Blocked by` section, `Depends on:`,
   `Starts after`, `Carried from`), or with `--conflict
   <path>...` naming the files it and an issue an agent has would edit in ways a merge cannot settle (give both to one
   agent in sequence). Same subsystem, same agent and "in order" are not reasons; the command refuses them
   ([Starting work](starting-work.md#parallel)); or `gds issue unblock <repo>#N` for an unblocked one.
3. **Blocks have a reason.** `gds issue block` writes the label `S-blocked` and a `Blocked (<who>, <date>): waits on #N:
   <why>` line (or `waits on the maintainer: <why>`) in the body. The coordinator's hand-written form since 2026-11-02,
   `Blocked (coordinator, 2026-11-02): waits on #227 (...)`, is parsed the same way (the issues named before the first
   colon, parenthesis or dash are the blockers; an open pull request counts as open). The command writes only a block
   it can back: the blocked issue's body names #N (its `### Blocked by` section, `Depends on:`, `Starts after`,
   `Carried from`), or `--conflict` names the files
   (`(conflict in: ...)` after the reason), or it waits on the maintainer (on 2026-11-02 four bot issues were chained
   behind one running issue as "the same bot brain, in order", none needing what it made, and five issues sat still).
   `gds issue list` shows the reason and its class (`[dependency]`, `[conflict]`, `[maintainer]`, or `[none named]` for
   a hand-written block its issue body does not back) of each blocked issue, and lists under "Unblocked: label to
   remove" those whose blockers all closed, so a block cannot outlive its cause. A block on the maintainer, on an issue
   of another repository, or with no recognisable issue is never lifted by itself.
4. **It cannot hold the coordinator forever.** It counts its own refusals per session (`session_id`) in
   `<workspace>/cache/idle-check-refusals.json` and allows the end after `max_refusals` (2) in a row, like the
   [stall gate](#stall) (`stop_hook_active` cannot count past one, so this check ignores it). The count is forgotten
   when nothing is idle and lapses an hour after the last refusal, so an ignored idle issue is raised again later.
5. **It only reads, and fails open.** The `gh` reads are cached for `cache_seconds` (60) in
   `<workspace>/cache/idle-check.json`, so a Stop every few seconds asks GitHub once a minute, within `budget_seconds`
   (40) in all. Every `gds issue start|block|unblock|release` removes the cache, so the next Stop sees the change at
   once. A repository GitHub cannot answer for (offline, rate limit, no access) is left out: a check that cannot look
   finds nothing and the session ends.

What it cannot see: two idle issues that conflict with each other (the coordinator judges that, and blocks one `--on` the
other), and an agent that holds an issue but has stalled (the [stall gate](#stall) and `gds issue list` show that). The
hook is registered for `Stop` already; restart the session to pick it up. A game gets nothing of this: the check reads
the workspace, not a repository, so only the kit's `.claude/settings.json` needs it.

## Docs ship with the change {#docs}

The learning loop below starts from a maintainer message. This part starts from the agents' own work: what they got
wrong updates the topic section it belongs to, by the agent that found it, in the same task
([Learning in the topic pages](rules.md)), and the next agent reads it before it starts.

- **Topic sections, not lesson pages.** A mistake updates a section of the page an agent reads for that task:
  `- **Approach:** ... **Watch out for:** ... **Seen:** ...` under a `##`/`###` heading with an explicit `{#anchor}`,
  named elsewhere as `page.md#anchor`. `gds learn <words>` prints the closest sections and their entries first, so the
  agent sharpens one instead of writing a duplicate; a new section has a reason line starting `<!-- new section:` (a
  new page too, never `new page:`), and a new page is made only when a topic outgrows its 50 KB. `docs/lessons/` (963
  files in a week, many on the same subject, where no agent looked while working) was emptied into the topic pages by
  #770 and takes no new file.
- **The checks.** `python .github/scripts/mistakes.py check` runs in the `topic-sections` pre-commit hook, in pytest
  and in the docs job of CI ([the list](rules.md#checks)). From the checkout it refuses a page over the limit, an entry
  without its three parts or over 900 characters or outside an anchored section or in the old `**Rule:**` form, a
  malformed or repeated anchor, a `##`/`###` heading without an explicit anchor under `studio/`, `engines/`, `tools/`
  or `gamedev/`, and a corrections-log row that quotes the maintainer or links no section. Against the
  base (where the branch left `origin/main`; CI checks
  out two commits and passes `--base HEAD^1`) it refuses a file added to `docs/lessons/` and a new heading without its
  reason line.
- **No categories.** There are no lesson areas and no glossary (gdstudio #771 removed `docs/lessons/areas.toml`,
  `gds lessons` and `mistakes.py render`): what an agent reads is named by section.
- **Named in the prompt, checked by the guard.** The coordinator runs `gds brief <owner/repo>#N` before every Agent
  call and puts its `Read: <page>.md#<anchor>` lines in the prompt ([Starting an
  agent](starting-work.md#starting-an-agent)). The PreToolUse guard on the Agent tool, which sees the prompt (it
  already checks `Issue:` and `PR:`), refuses a task agent with no `Read:` line naming a section, or with one naming a
  section the kit checkout's `docs/` does not have (`lessons.missing_refs`: no such page, or no such anchor on it); the
  refusal names the missing sections and the `gds brief` command for the prompt's issue. A `Read:` line may list
  several sections, or be followed by list lines that each name one. Helpers, the reviewer and `general-purpose` are
  exempt; `[brief] enforce = false` turns it off; a kit whose `lessons.py` cannot be loaded checks only that a line
  names something shaped like a section. `SubagentStart` adds no sections: it tells the agent to read the ones its
  prompt names and what its report says. It used to guess them from a ten-minute note the guard left
  (`cache/subagent-pending.json`) and inject the newest items of the issue's areas; both are gone.
- **Unpublished docs.** At `Stop` and `SubagentStop`, a branch of a worktree under `<workspace>/worktrees/gdstudio/`
  with commits ahead of `origin/main` and no open or merged pull request (one `gh pr list` for the kit) holds the
  session back once, naming the branch. If GitHub cannot be asked, the hook lets go.
- **Only its own branches.** The gate names a branch the session owns (`owned_kit_worktrees`): the worktree of its
  `cwd`; the one its prompt names (`Worktree:`) or the ledger holds for its `Issue:` (read from the first user messages
  of its transcript); one named in its `git commit`, `git worktree add` or `git merge` commands. A session that owns
  none (an eval run, the coordinator) is never held for others' branches; the check below does the same.
- **Commits after a merge.** The same list gives the tip a branch's last merged pull request landed (`headRefOid`).
  A merged branch (none open) that then got a commit is also named, when `git cherry origin/main HEAD <tip>` marks the
  commit `+` (by patch id, since a squash merge rewrites every hash). The message says to make a new branch from
  `origin/main`, cherry-pick the commit, open a new pull request, and reset the old branch. A commit
  that reached `origin/main` through a new pull request has the same patch id and is not named; one squashed there
  with others is read by content: stranded only if a path it touches differs from `origin/main`'s blob. If the tip is
  unknown in the worktree (the branch was rewritten), the hook lets go ([Landing](landing.md#landing)).
- **The report.** `SubagentStop` reads the agent's last message (`last_assistant_message`, else the end of its
  transcript). A non-empty `Mistakes` section (a heading, or `Mistakes:` / `**Mistakes**`; `none` is empty) must name a
  section as `page.md#anchor` that a kit worktree (or the kit checkout) has, with that anchor, and changes against
  `origin/main`: the rule was written there. A file of `docs/lessons/` or the corrections log (its page or a page of
  `studio/corrections-log/`) does not count. Otherwise the agent is held back once. A task agent's report that names a
  pull request also needs a `Read:` line naming the sections it read and a `Docs gaps:` line (`none` is fine), or it is
  held back once ([The report](starting-work.md#the-report); `[brief] report`); a `Blocked:` end is not judged. A
  `Read:` or `Docs gaps:` line ends a `Mistakes` section, so `Mistakes: none` above them stays empty, and a section
  named only on a `Read:` line is one the agent read, so it never satisfies the Mistakes check. Helpers and the
  `reviewer` are exempt. Settings: `[docs]` and `[brief]` in `hooks.toml`.

- **The pull request.** The `body` check of `pr.yml` judges the description with what GitHub knows
  (`groundwork.py pr-history` lists the watched checks that failed on an earlier commit and the issues the pull request
  closes with their labels; a check that failed only because a newer push cancelled its run, which `build-ok`
  reports as a failure when a job it needs was cancelled, is not counted) and with its changed files. It counts as an
  agent correcting earlier work when its title verb is `Fix` or `Rework`,
  when a check of `pull_requests.lessons.history_checks` failed on an earlier commit of it, or when an issue it closes
  is labelled `bug` (the nearest signal to "a fix to an agent-caused issue"). Such a pull request needs
  `Lessons: <page.md#anchor>` in Summary, naming the topic section it updates; with `lessons.names: section` an
  old lesson file or the corrections log is refused, and with `lessons.edited` the section's page must be among the
  pull request's changed files (`check-body --changed`; `gds pr check-body` and the guard pass the branch's files).
  `Lessons: none (reason)` is refused for it; elsewhere the line is optional. A pull request that closes an issue
  needs `Read first: <page.md#anchor>, ...` naming the sections its author read (the `Read:` lines of its brief); a
  value with no section in it is refused, and in the kit (`read_first.docs: docs`) each section must exist in the
  base branch's docs (on a machine, `origin/main`'s: [the body guard](pull-requests.md#pr-body)). A game's
  conventions have no `docs` key (the kit's docs are not in its checkout), so only the form is checked there. A game's
  conventions add `Kit docs: <kit pull request>` (or `none (reason)`) for a `Fix`, a `Rework` or a `bug` issue
  (`pull_requests.kit_docs`, same script): a game's rules live in the kit's sections. If GitHub cannot be asked, the
  title alone is judged.
  Every `none (reason)` line (`Lessons`, `Kit docs`, `Failed first`, `Issues affected`, `Screenshots`, `Before`) takes the
  reason in parentheses with one full stop after it, and refuses any other text after the parenthesis.

What it cannot see: a mistake the agent does not report (the report is the agent's own), a rule that is well formed
but says nothing, and a correction that fails no check and carries no `Fix` title. The reviewer looks for them
([what no program sees](rules.md#unseen)). A game takes the `pr-history` command and the rules when its
`.github/scripts/groundwork.py` and `conventions.yml` are updated from the kit's, in a pull request of its own; a
game's `lessons` rule without `names: section` keeps the old form.

- **Approach:** Update the research page a pull request builds on in that pull request, and land each maintainer
  correction on the corrections log the same session. **Watch out for:** findings stayed in agent reports and pull
  request bodies, where the next agent never reads them. **Seen:** Deadnight, 2026-11-01 (fix: the docs hook holds a
  change back until its docs ship with it).
- **Approach:** Write the docs for what was not planned at the start in the same task as the fix, by the agent that did
  it, and count an agent's own corrections (a red check, a rework) as mistakes to record too; read the rules of an area
  before a task in it. **Watch out for:** the learning loop fired only on a maintainer message: #507's hand-grip docs
  sat on a kit branch for a coordinator batch, two lessons sat unpushed, nothing tied a game pull request to its kit
  docs, and an agent's own fixes left none. **Seen:** Deadnight #507, gdstudio #99, 2026-11-02 (fix: the Stop and
  SubagentStop gates flag a kit branch with commits and no pull request and a report with mistakes and no section; `gds
  issue start` puts the rules of the issue's areas into the agent's context (gdstudio #99)).

- **Approach:** Judge a Stop gate against the stopping session's own work: name only the branches it owns (its `cwd`,
  prompt, ledger entry and commands). **Watch out for:** a gate over every kit worktree held each agent, the
  coordinator and eval runs to disclaim the others' branches, and ate an eval run's report.
  **Seen:** gdstudio #895, 2026-11-10.

## Agent stalls {#stall}

A background task agent whose turn ends is finished for good: nothing wakes it, `ListAgents` still says `running`, and
nothing shows on GitHub. It happened three times on 2026-11-02 (the agents ended on "Now the autopilot." and the like;
[Agents](agents.md#the-loop)). The rule in the agent
definitions did not stop the third, so `SubagentStop` now refuses such an end. Settings: `[stop_check]` in `hooks.toml`.

1. Only the agent types in `[stop_check] agents` are judged: `godot-engineer`, `backend-engineer`, `blender-artist`,
   `level-designer`. The `reviewer`, the helpers and every other type are never touched.
2. The agent's last message (`last_assistant_message`, else the end of its transcript) is a **report** when it matches
   `[stop_check] report`: a pull request link (`github.com/.../pull/N`) or `PR #N` / `pull request #N`; a `Mistakes`
   heading or label (every report has one, [Docs ship with the change](#docs)); a line that starts `Blocked:` or
   `Blocker:` (a dash works too, and bold); `stopped because`; `I am blocked`. Anything else, such as "Now the
   autopilot.", is a stall and gets `decision: block`, whose `reason` Claude Code gives to the agent as its next
   instruction: do the step now, or wait on a background command, or end with a report or `Blocked: <what stops you>`.
3. It lets go, and never counts, when: the agent has a background task running (`background_tasks` in the input is
   not empty: it is waiting for the notification, which does wake it); there is no message to read (a guard that
   cannot look lets go); or the session is not in a GDStudio workspace.
4. **It cannot hold an agent forever.** Refusals are counted per agent run (`agent_id`) in
   `<workspace>/cache/stop-check.json` (entries older than a day are dropped); after `max_refusals` (2) the end is
   allowed. `stop_hook_active` cannot count past one, so this gate ignores it. The refusal's text says which refusal it
   is. An agent that really cannot go on has the way out in the reason: a `Blocked:` line passes at once.
5. **A let-through end resets the count.** When the end is allowed because the message reads as a report, or because the
   limit was reached, the agent's entry is removed from the file. An agent that is resumed (`SendMessage`) and stalls
   again, even the same day, gets its own `max_refusals` refusals; before this, the spent count of its first stall let
   the second one through ([#156](https://github.com/Ryubara/gdstudio/issues/156)).

The hook uses the message alone. The first design in [#148](https://github.com/Ryubara/gdstudio/issues/148) also asked
whether the agent's issue already has a pull request, but the ledger (`gds issue start`) is keyed by issue and records
the agent's *name*, while `SubagentStop` carries only `agent_type` and `agent_id` (not the prompt or the name), so the
two cannot be joined without parsing the transcript. A stall after the pull request is open is the same stall, and the
check would need `gh`. What it cannot see: a stall written as a report (a message that names a pull request and
announces a step is let through), and a stall by an agent whose end is a tool call with no text.

What the gate lets through (an agent that waits on a background task) can still end for good when that task ends
without waking it, or when a `/clear` kills it. Tether keeps a record of the subagents it saw at work and tells the
coordinator, once, at the next session start (new, resumed or after a clear), each one that ended without a report,
with its last status line ([tether #31](https://github.com/Ryubara/tether/issues/31)).

Both registrations already exist (`.claude/settings.json`; the game template's `launch.py` runs the same dispatcher),
so a game gets the gate with `gds sync`; restart sessions to pick it up.

## Proof {#proof}

At Stop, a session that changed visual files of a game (scenes, shaders, `game/ui/`, `game/assets/`, `game/world/`)
is held back once until a capture newer than those changes sits in `<workspace>/scratch/<repo>/<branch>/`. The reason
names the folder and the Movie Maker command.

## Session start {#session-start}

Each session is told its workspace, repository and branch, the pinned tool paths, and its branch's scratch folder,
and to read the checks of the corrections page that touch its task (see [Learning](#learning)); under the soft disk
limit, the free space and the rule to keep its output small ([Disk](#disk)). It fires on `startup`,
`resume`, `clear` and `compact`.

## Local mains {#mains}

Every repository in `<workspace>/repos/` that has `main` checked out follows origin: the maintainer opens those
checkouts in the editor, so they show what has merged. `git pull --ff-only` runs right after a shell command that
merges a pull request (`gh pr merge`, `gh api .../pulls/<n>/merge`, a `PostToolUse` hook), at session start, and at
Stop at most once every two minutes (auto-merges land without a command). It never discards: a checkout whose local
changes are in the way, or one on another branch, is left alone and named in the session's context. Settings:
`[mains]` in `hooks.toml`.

- **Approach:** Keep every local `main` checkout fast-forwarded after each merge by a hook, never by memory, and name a
  checkout with local changes instead of discarding it. **Watch out for:** merges landed on GitHub, most by auto-merge,
  while the local main checkouts the maintainer opens in the editor stayed behind. **Seen:** Deadnight, 2026-11-01 (fix:
  the hook above pulls after a merge command, at session start and at Stop).

## Finished worktrees {#sweep}

`gds worktree sweep` ([the rules](workspace.md#sweep)) is started in the background at session start, right after a
shell command that merges a pull request, and at Stop, at most once every ten minutes (`[sweep]` in `hooks.toml`). The
hook only starts the process and returns, so it never blocks or delays a session; the sweep takes a lock file
(`cache/worktree-sweep.lock`, taken over after half an hour), so sessions that start together run one sweep, and it stops
by itself after 20 minutes. Its report is appended to `scratch/worktree-sweep.log`. On Windows the process is started
with `CREATE_NO_WINDOW`, so neither it nor its git children flash a console window
([Agents](agents.md#the-loop)). `enabled = false` turns it off and
`args = ["--no-idle"]` limits it to the pull request and issue rules.

## Disk {#disk}

`gds disk guard` ([the rules](workspace.md#disk)) is started in the background by every hook event in a workspace (a
tool call, an agent's start and stop, a session's start and stop), at most once every `every_seconds` (300) by the age
of `cache/disk-guard-started`: while anyone works it runs every five minutes. Like the sweep, the hook only starts it and
returns; the guard takes its own lock (`cache/disk-guard.lock`), runs the sweep under the sweep's lock (skipped when
another sweep holds it), appends its report to `scratch/disk-guard.log` and writes `cache/disk-guard.json`.

Under `soft_gb` free, SessionStart and SubagentStart add a line to the context: the free space, the folders over
budget, and the rule to reduce downloaded CI artifacts to their numbers and delete them in the same task. Under
`hard_gb` free, the PreToolUse guard refuses an Agent call that starts a task agent (helpers and `[disk] exempt`, the
`reviewer`, still start) and `git worktree add`; `gds issue start` refuses by itself. The refusal names the free space
and the five biggest folders of the last guard run. The free space is read with one `shutil.disk_usage` call, so the
check costs nothing; a disk that cannot be read lets the call through. `enabled = false` turns the guard and the
refusals off.

## Learning {#learning}

A mistake is written into the docs in the same session, so the next agent gets it right the first time: as an entry in
the topic section it belongs to ([Learning in the topic pages](rules.md)). A maintainer correction also gets a line on
the [corrections log](maintainer-corrections.md). Four hooks make it happen, all in the one dispatcher; their texts are
the `[lessons]` keys of `hooks.toml`.

A rule, a log line or a queued file says what the maintainer decided or pointed out in our words, with the issue or
pull request and the date as its source. The maintainer's prompts are never quoted, word for word or nearly, in a
committed file or in an issue or pull request body an agent writes; the checks fail a log row with a cell that starts
with a quotation mark (gdstudio #780).

| Event | What it does |
| --- | --- |
| `UserPromptSubmit` | Adds a two-line reminder to every message in a GDStudio workspace: if this message corrects an agent or reports a problem in earlier work, update the topic section it belongs to (`gds learn <words>` finds it; never a lesson page) and a line on [the corrections log](maintainer-corrections.md) (what the maintainer pointed out in our words, with its issue or pull request and date and never a quote of the prompt, linking the section), in a kit pull request in this session. If the cause is not known yet, queue it. |
| `SessionStart` | Tells the session to run `gds learn` on its task and read the rules it prints, and that a mistake becomes a rule in its section. |
| `SubagentStart` | Tells every project agent to read the sections its prompt's `Read:` lines name (the Agent guard made sure they exist, [above](#docs)), that its report names them with a `Docs gaps:` line, and that an agent whose task came from a correction puts the log line in its final report: the coordinator publishes it, so many agents never edit one page. It injects no sections. Read-only helpers (`[agents] helpers`) get nothing. |
| `Stop` | Holds the session back once while a queued correction is unpublished (below). `stop_hook_active` lets the next stop through, so it never loops. |

**The queue.** A correction whose cause is not known yet is a Markdown file in `<workspace>/scratch/kit-lessons-queue/`
(`[lessons] queue`, relative to the workspace): a title, what the maintainer pointed out (in our words, with its
source), and what is known. A file that says `Waiting on: #N` (the issue that finds the cause) is left alone. When the
cause is found, the rule and the log line are published in a kit pull request and its file moves to `published/`. The
Stop gate lists every other file in the queue folder. It applies to any session in the workspace; corrections that are
not yours: say so and finish.

Registered in `.claude/settings.json` and in the game template (`templates/game/.claude/settings.json`, which
`gds sync` writes into each game): restart sessions to pick the hooks up.

- **Approach:** Tie every maintainer correction to a docs change by hooks: a reminder on every prompt, the rules read at
  session and agent start, and a stop gate on corrections not yet published. **Watch out for:** learning from
  corrections depended on the coordinator remembering; nothing tied a correction to a docs change, and agents did not
  read past corrections before starting. **Seen:** Deadnight, 2026-11-01 (fix: the learning hooks (kit #72)).

## The guards' modules {#modules}

<!-- new section: the page said what each guard refuses, never where its code lives; guards.py became a package -->

The dispatcher runs the package `.claude/hooks/guards/`, one module per job, so two hook changes rarely touch one file.
Standard library only: the hooks start under `uv run --no-project`.

| Module | Its job |
| --- | --- |
| `__init__.py` | the entry points the dispatcher calls: `pre_tool_use`, `post_tool_use`, `stop` and `subagent_stop` run the guards of every module, each importing the modules it needs when it runs |
| `shell.py` | reading a shell line: heredocs left out, simple commands as words, the program, the folder of `git -C` and `cd`, a flag's values |
| `workspace.py` | the tool groups, the warnings of a guard that failed open (`take_warnings`), globs, git, the workspace by its marker, the kit (`KIT`, `kit_root`), `load_kit_module`, and `gds` commands started in the background |
| `agents.py` | agent types, and the `Read:` lines of a task agent's prompt ([below](#docs)) |
| `issues.py` | issue order and the labels of progress ([below](#issues)) |
| `bodies.py` | pull request bodies before `gh pr create\|edit` runs and after it ran ([the image guard](pull-requests.md#attach-paths)) |
| `commits.py` | commits and pushes |
| `merges.py` | `gh pr merge`, manual paths and the hold ([above](#hold)) |
| `behind_base.py` | a merge only of a head that holds its base's tip |
| `comments.py` | no comment or review under the maintainer's account ([above](#comments)) |
| `launches.py` | pinned tools, windowed Godot, Godot audio, browser probes, kills by name |
| `protected.py` | secrets printed, protected and generated files edited |
| `proof.py`, `session.py`, `mains.py`, `disk.py`, `sweep.py`, `learning.py`, `docs.py`, `stall.py`, `idle.py` | the sections of the same names below |

A module imports what it uses from another (`from .shell import segments`), and `guards.<name>` still finds any name
of the package (a module `__getattr__`), as it did when the guards were one file. The entry points import a module
when a call needs it: a Read loads `disk.py` and `workspace.py` only, a shell command the `git` or `gh` guards only
when it runs `git` or `gh`. The three kit modules the hooks load
by file (`gds_tools/pr.py`, `lessons.py`, `issues.py`) go through `load_kit_module(name)`, so they must use the
standard library only; `python/tests/hooks/test_hook_modules.py` loads them under `python -I -S`.

- **Approach:** Replace a name of the guards in a test with `hook_support.patch(monkeypatch, name, value)`
  (`python/tests/hook_support.py`), which sets it in every module of the package that holds it. **Watch out for:**
  `monkeypatch.setattr(guards, name, ...)` changes only the package's binding, so the guard that imported the name
  still calls the real one and a test reaches GitHub or the real disk; and a module named like one of the package's
  functions hides it, because importing `guards.behind` set the package's `behind` to the module (hence
  `behind_base.py`). **Seen:** gdstudio #929, 2026-11-11 (the split; `guards.behind(...)` raised "'module' object is
  not callable" until the module was renamed).

- **Approach:** Import a guard module inside the entry point that calls it, and time a hook change against the code
  before it, interleaved (A, B, A, B) on the same payloads, Read among them. **Watch out for:** the PreToolUse hook
  runs on every tool call (matcher `*`), so each module imported with the package costs every Read and Grep a file
  open; the twenty modules imported at once cost 10 to 15 ms more than the single file, a run of one after the other
  hides it in noise. **Seen:** gdstudio #929, 2026-11-11 (fixed by imports in `pre_tool_use`; a Read went from 120 to
  115 ms, a shell command stayed within noise).

## Tests {#tests}

How the run works (the command, CI's four workers, the seeded repositories of `python/tests/git_seed.py`, the
allowed skips) is on [The kit's tests](kit-tests.md); this section says which file covers which hook.

`python/tests/hooks/` covers every guard, one file per job as [the modules](#modules) are (`test_hook_<job>.py`; its
`conftest.py` keeps every test away from GitHub, the sweep, the disk guard and the real disk): the comment guard (one
case per route, spelling and mutation, and one per command that must keep working), the answer protocol, the fail-open
path, the issue-order checks, the stall gate (reports, blockers, the refusal limit, the reviewer), the idle-issue check
(the refusal and both commands, a task agent never judged, the refusal limit and its reset, the `gh` cache, failing
open) and the learning loop (each event's text, the queue gate and its loop guard, and the dispatcher run as a process)
and the background sweep (started once, throttled, switched off, log moved aside; started by session start, a merge and
Stop).
`python/tests/test_sweep.py` covers `gds worktree sweep` on real git repositories.
`python/tests/test_brief.py` and the brief tests of `python/tests/test_lessons.py` cover `gds brief`: an issue and a
pull request read through recorded `gh` answers, the order of the proposed sections, a path mention far from the issue's
words left out (#909's body in `python/tests/fixtures/issue_bodies/`), and that the kit's own brief names sections that
exist; `hooks/test_hook_issues.py` and `hooks/test_hook_docs.py` cover the `Read:` guard and the report's `Read:` and
`Docs gaps:` lines.
`python/tests/test_issues.py` covers the window, `gds issue` (including `block`, `unblock` and the parsing of the
`Blocked (...)` line) against `gh` JSON recorded in `python/tests/fixtures/`.
