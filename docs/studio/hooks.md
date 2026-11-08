# Hooks

Claude Code hooks are the rules enforced *while* an agent works, before anything reaches git or GitHub. Every event
goes to one dispatcher, `.claude/hooks/dispatch.py`; a game runs the same one through its `.claude/hooks/launch.py`,
which finds the kit by the workspace marker. Settings: `.claude/hooks/hooks.toml` (a game may override keys in
`.claude/hooks.local.toml`).

## What it refuses

| Guard | Refuses | Instead |
| --- | --- | --- |
| Agents | `general-purpose`, or an Agent call with no type | a project agent (`.claude/agents/`) or a read-only helper |
| Unpublished docs | an agent finishing, or a session stopping, while a branch of the kit's worktrees has commits and no pull request, or commits made after its pull request merged; an agent's report with a `Mistakes` section and no lesson file | push the branch and open its pull request; write the lesson (docs/studio/hooks.md#docs) |
| Agent stalls | a task agent (`godot-engineer`, `backend-engineer`, `blender-artist`, `level-designer`) finishing on a message that is not a report: no pull request link or number, no `Mistakes` section, no `Blocked:` line, and no background task running | do the announced step in the same turn, or end with the report or `Blocked: <why>` ([below](#stall)) |
| Idle issues | the **main session** (the coordinator) ending a turn while an issue in any repository of `workspace.toml` may start now (the window's "May start now", or blocked with a blocker that has closed) and has no agent; never a task agent | start each (`gds issue start`), or take it out of the line with a reason (`gds issue block <ref> --on <#N\|maintainer> --why "..." [--conflict <path>...]`) ([below](#idle)) |
| Issue order | a task agent whose prompt names no started issue (`Issue: owner/repo#N`) or open pull request (`PR: owner/repo#N`); `gh issue edit\|create --add-label S-in-progress`; `S-in-progress` on a pull request; `P-critical` from a session | `gds issue start <ref> --agent <name>` ([Starting work](starting-work.md)) |
| Disk | under `[disk] hard_gb` free (10 GB): a task agent's start, `git worktree add` (and `gds issue start`) ([below](#disk)) | `gds disk guard`; report what is left to the coordinator and the maintainer |
| Git | commits or pushes on `main`; force pushes; `--no-verify` | a branch in a worktree, a pull request |
| Merge | `gh pr merge --admin`; merging a pull request that changes a manual path | let checks pass; report it to the maintainer |
| Hold | a merge command (`gh pr merge`, with or without `--auto`, or `gh api .../pulls/<n>/merge`) on a pull request carrying `S-hold`; taking `S-hold` off (`--remove-label`, a `gh api` write, `gh label delete\|edit`); GraphQL merge and label mutations ([below](#hold)) | stop and report; only the maintainer takes a hold off |
| Comments | any `gh` command that posts a comment or a review under the maintainer's account: the `comment` commands, `gh pr review`, `--comment` or `-c` on a close or reopen, `gh api` writes to a comments or reviews path, GraphQL mutations ([below](#comments)) | the same command without the text; the text goes in the scratch folder and the report |
| Tools | Godot or Blender from Steam or PATH | `gds tool path godot\|blender` |
| Windowed Godot | Godot started from a shell without `--headless`: its window takes the keyboard focus (docs/engines/godot/no-focus.md) | `gds godot -- <arguments>` or `gds capture frames`; `--headless` when nothing is drawn |
| Godot audio | a Godot started with a real `--audio-driver` (not `Dummy`), or `gds godot --with-audio`: it plays through the speakers of the person at the machine (docs/engines/godot/no-focus.md#sound) | drop the option: `gds godot` adds `--audio-driver Dummy`, `--headless` and Movie Maker force it |
| Browser probes | a `tools/web_smoke/*.py` script or a Playwright run (`playwright test`, `uv run --with playwright python x.py`) not wrapped in `gds quiet`: headless Chrome under pointer lock clips the person's cursor (docs/engines/godot/no-focus.md) | `gds quiet -- <command>` |
| Pull request images | `gh pr create\|edit --attach <file>` whose body file (`--body-file`, or a literal `--body`) does not refer to every attached file inside `## Screenshots` by a path that names the same file as `--attach` (`./x.png` is `<the folder the command runs in>/x.png`, [below](#attach-paths)), has no image between `Before:` and `After:` (unless `Before: none (reason)`) or none below `After:`, or cannot be read before the command runs (`[attach]` in `hooks.toml`) | write the body to a file with `![before](../before.png)` / `![after](../after.png)` on those lines, `cd` into the folder that holds the images, then `--body-file <file> --attach ./before.png ...`; read the body back |
| Local images left in a pull request | after a shell command that opened or edited a pull request, or printed one's address as its last line (a script, an alias): the description read back from GitHub still has a `![x](../x.png)` reference that is not an upload (`readback` in `[attach]`) | the answer names the references; fix the description at once ([below](#attach-paths)) |
| Pull request body | `gh pr create\|edit` with a `--body-file` (or a literal `--body`) that `groundwork.py check-body` refuses: the rules `pr-rules` runs after the push (`[pr_body]` in `hooks.toml`, [below](#pr-body)) | fix the body file, check it with `gds pr check-body <file> [--title <file>]`, then run the command |
| Kills | stopping Godot or Blender by name (`taskkill /IM`, `pkill`, `killall`, `Stop-Process -Name`): every agent's run dies | kill your own process by its PID |
| Secrets | printing a key-like variable; dumping the environment | test that it is set |
| Files | editing secrets, caches, git internals, pinned tools; generated files | edit the source (`conventions.yml`, then render) |

All reasons come back at once. A refusal is Claude Code's JSON answer with exit code 0; if the dispatcher itself
fails, the call is allowed and the error printed, so a broken guard never locks a session out.

## Pull request bodies before they are sent {#pr-body}

`pr-rules` judges a description after the push, and an agent whose body failed only found out there (a `None` line
without its reason, text after it, a missing section). `gds pr check-body <file> [--title <file>] [--repo <folder>]`
runs the same function, `groundwork.py check-body`, on the machine and exits 1 with the reasons (2 when it cannot run:
no conventions, not a checkout). It runs in the checkout of the repository the pull request is for and reads that
repository's `.github/conventions.yml`, with its own `.github/scripts/groundwork.py` when it has one (a game's rules
differ from the kit's), else the kit's. The Git/GitHub guard does the same before `gh pr create|edit` runs: it reads
the body once, the same read `--attach` uses, runs the check in the checkout around the current folder (or the
`<workspace>/repos/<name>` checkout that `-R owner/name` names, when that is another repository) and refuses with the
reasons and the command to run. `--title` on the command turns on the title rules (screenshots, failed first, lessons).
Not judged, because they cannot be read first: a body from standard input, a file not written yet, a literal body with a
backtick or `$(`, a `gh pr edit` without a body, and a repository with no checkout. The pull request's history is not
asked (no network), so "a check failed on an earlier commit" is still `pr-rules`' alone to judge.
A `](../path)` reference to a file the same command passes with `--attach` (the same file, [below](#attach-paths)) counts
as an uploaded capture there (the guard swaps in an upload address before it asks, as `--attach` does), so one body
satisfies both guards; a reference to a file that is not attached, or the same body without `--attach`, is refused.
`gds pr check-body` by hand has no `--attach` and still wants uploaded captures
([lesson](../lessons/2026-11-02-gh-pr-create-attach-is-refused-by-the-body-check.md)). A relative `--body-file` is read
from the folder the command is in after its `cd` (`cd <dir> &&` or `cd <dir>;`, quoted paths, `cd /d`, `~` and Git
Bash's `/c/dir` included), the way `gh` reads it. A `cd` the guard cannot follow (`cd -`, `cd $DIR`, a glob) leaves a
relative body file unplaced: `--attach` is then refused with "use an absolute path", and without `--attach` the body
is not judged. The refusal for a missing file names the path it looked in
([lesson](../lessons/2026-11-02-the-body-guard-read-a-relative-file-from-the-wrong-folder.md)). `--attach` paths are never
opened by the guard, only placed and compared with the references ([below](#attach-paths)). The docs rule of
`pr-rules` (code changed, no docs changed, no `Docs: none` line) reads the branch's files: `gds pr check-body` and the
guard run the same `groundwork.py check-docs` on `git diff --name-only origin/main...HEAD` of the checkout. With no
branch to read (no commit, a detached head, the checkout on `main`, no `origin/main`) `gds pr check-body` prints
`docs: cannot tell` rather than `docs: ok`, and the guard lets the command through
([lesson](../lessons/2026-11-02-the-local-body-check-skipped-the-docs-rule.md)). The guard is a hand-merge path
(`.claude/hooks/`): a maintainer merges changes to it.

- **Approach:** Give the pull request template an Issues affected section and a Failed first test from the first day,
  and update every affected issue after a merge. **Watch out for:** follow-up work and real regressions went untracked
  when a pull request had nowhere to name them. **Seen:** Deadnight, 2026-11-01 (fix: the template carries both sections
  and the body check reads them before a pull request is sent).
- **Approach:** Run `groundwork.py check-body` on a pull request body before opening it. **Watch out for:** a body wrote
  `None` without the expected form, and the body check in CI refused it after the pull request was open. **Seen:**
  Deadnight, 2026-11-01 (fix: the CI body check caught it; the hook here now checks a body before it is sent).

## Which paths the image guard covers {#attach-paths}

`gh pr create|edit --attach` uploads each file and rewrites a `![alt](../path)` reference in the body to the upload, in
place, **only when the reference and the `--attach` path name the same file**. `gh` places both from the folder it runs
in. With the command run in the worktree, `--attach <scratch>/before.png` and `![before](../before.png)` are two files:
the reference stays `./before.png`, the upload is appended after `## AI use`, and `pr-rules` fails with "the 'Before:'
capture is missing". Measured on 2026-11-03 with `gh` 2.102.0 (`gh issue edit --attach` shares the code):

| `gh` runs in | `--attach` | reference in the body | rewritten in place |
| --- | --- | --- | --- |
| the worktree | `<scratch>/x.png` | `./x.png` | no (the upload is appended after `## AI use`) |
| the images' folder | `<scratch>/x.png`, `./x.png` or `x.png` | `./x.png` or `x.png` | yes |
| the worktree | `<scratch>/x.png` | `<scratch>/x.png` | yes |
| the worktree | `<scratch>/x.png` | a relative path that resolves to it | yes |

The guard before the command used to match by file name alone, so it passed the first row. Deadnight #611 and #637
were opened that way through the Bash tool, which the guard does see: the body file was written first, `--attach` took
absolute paths in the scratch folder, and the command ran in the worktree (the agents' transcripts; the body history
on GitHub shows the first body with `](../before-desktop-2-solo.png)` references and the uploads appended). The same
history shows 17 Deadnight pull requests of 2026-11-02 and 03 with a description revision that had `./` image
references. The guard now places the reference and the `--attach` path (`file_key` in
`.claude/hooks/guards.py`, following a plain `cd`, `pushd` or `Set-Location`) and refuses the pair that is not one
file, naming both paths and the folder `gh` would read from. The Bash and PowerShell tools are judged alike. A `cd` it
cannot follow (`cd $DIR`) leaves a relative reference unplaced, so it is refused too. The body guard reads the same
placing (`as_uploaded`): a `./x.png` reference that `gh` would leave local stays local for the description rules, and
the two guards agree.

Paths the guard cannot read are covered by a second line, a `PostToolUse` read-back. After a shell command that ran
`gh pr create|edit`, or whose last output line is a pull request address (a script that runs `gh`, an alias), the
description is fetched (`gh pr view <url> --json body`) and any `![x](../x.png)` reference to an image that is not an
upload is named in the answer, with the command that repairs it. It is advice, not a refusal (the pull request already
exists), and `readback = false` in `[attach]` turns it off. Neither check can read a script file (`python open_pr.py`
runs `gh` out of sight; only the read-back sees its result) or a `gh api` call that sets a body; `pr-rules` in CI
remains the last check.

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
- **The guard** in `guards.py` gives a session the reason, and it is the only thing that stops a session taking the
  label off: every agent uses the maintainer's token, so GitHub cannot tell them apart. It reads shell commands, so it
  does not see a script that calls the API itself.
- **A pull request opened before the check was required** has no run on its head and stays pending: run
  `gh workflow run hold-sweep.yml` once. It reports the check through the Checks API and does not touch the pull
  request. A new game runs it once when its ruleset starts requiring `hold`.

Do not put an `if:` or a `paths:` filter on `hold`: a job skipped by `if:` reports success, so a filter on the label's
name would let any other label replace a failed run. `python/tests/test_hold.py` has a test for each such reason.

## Comments {#comments}

Nothing an agent runs posts a comment or a review under the maintainer's GitHub account (their decision of 2026-10-12);
status labels say that work is under way. `check_comments` in `guards.py` judges what `gh` would do, because a rule
that lists the commands named `comment` let `gh issue close --comment` post on #691
([lesson](../lessons/2026-11-05-a-closing-comment-passed-a-rule-that-listed-commands.md)). The routes come from every page
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
Until 2026-11-06 they did post, and this page called it by design
([lesson](../lessons/2026-11-06-a-guard-on-what-agents-type-missed-what-the-tool-posted.md)).
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
  agent sharpens one instead of writing a duplicate; a new section has a reason line, a new page is made only when a
  topic outgrows its 50 KB. `docs/lessons/` (963 files in a week, many on the same subject, where no agent looked
  while working) takes no new file, and #770 empties it.
- **The checks.** `python .github/scripts/mistakes.py check` runs in the `mistakes-by-area` pre-commit hook, in pytest
  and in the docs job of CI ([the list](rules.md#checks)). From the checkout it refuses a page over the limit, an entry
  without its three parts or over 900 characters or outside an anchored section or in the old `**Rule:**` form, a
  malformed or repeated anchor, a corrections-log row that quotes the maintainer or links no section, and an old lesson
  file without areas or dated after the folder closed. Against the base (where the branch left `origin/main`; CI checks
  out two commits and passes `--base HEAD^1`) it refuses a file added to `docs/lessons/` and a new heading without its
  reason line.
- **Areas.** The names, the issue label to areas map, the page prefixes and the placement keywords are in
  [`docs/lessons/areas.toml`](../lessons/areas.toml). The mistakes glossary has a section per area: the entries of the
  topic sections (placed by the longest `[pages]` prefix of their page, else by keyword), then the old lesson files by
  their `areas:` front matter. It is **not a file in the repository**: `gds lessons <area>` and the hook below build it
  in memory, and `python .github/scripts/mistakes.py render` prints it. It used to be committed, so every lesson pull
  request rewrote it and the second of two concurrent ones conflicted or went stale (#119).
- **Injected, not hoped for.** `gds issue start` maps the issue's labels to areas (`A-net` is net, web and backend; the
  `general` area is always there) and keeps them in the ledger with the issue's title. When the Agent guard lets a task
  agent start it leaves a note (`cache/subagent-pending.json`, ten minutes) with the areas and the title of the
  `Issue:` line; `SubagentStart`, which does not see the prompt, takes the oldest note for that agent type and adds two
  texts to the agent's context: the sections closest to the title with their rules (`gds learn <title>`, at most
  `learn_limit` sections and `learn_chars` characters), then the first `inject_limit` items of each area. A `PR:`-only
  agent gets the `general` area and no sections.
- **Unpublished docs.** At `Stop` and `SubagentStop`, a branch of a worktree under `<workspace>/worktrees/gdstudio/`
  with commits ahead of `origin/main` and no open or merged pull request (one `gh pr list` for the kit) holds the
  session back once, naming the branch. If GitHub cannot be asked, the hook lets go.
- **Commits after a merge.** The same list gives the tip a branch's last merged pull request landed (`headRefOid`).
  A branch whose pull request is merged (and none is open) and which then got a commit is also named, when
  `git cherry origin/main HEAD <tip>` still marks that commit `+`: the commits after the tip, compared to `origin/main`
  by patch id, because a squash merge rewrites every hash. The message says to make a new branch from `origin/main`,
  cherry-pick the commit, open a new pull request, and reset the old branch to the merged tip (so it is not named
  again). A commit that already reached `origin/main` through a new pull request has the same patch id and is not
  named; one squashed there with other commits has a new patch id, so each `+` commit is also read by content and is
  stranded only if some path it touches differs from `origin/main`'s blob (no checkout, no side effect). If the tip
  is unknown in the worktree (the branch was rewritten), the hook cannot tell and lets go. This is
  the gap that lost a lesson twice (kit #175 and #176;
  [lesson](../lessons/2026-11-02-a-lesson-pushed-after-its-pull-request-merged-was-lost.md)).
- **The report.** `SubagentStop` reads the agent's last message (`last_assistant_message`, else the end of its
  transcript). A non-empty `Mistakes` section (a heading, or `Mistakes:` / `**Mistakes**`; `none` is empty) must name a
  section as `page.md#anchor` that a kit worktree (or the kit checkout) has, with that anchor, and changes against
  `origin/main`: the rule was written there. A file of `docs/lessons/` or the corrections log does not count. Otherwise
  the agent is held back once. Helpers and the `reviewer` are exempt. Settings: `[docs]` in `hooks.toml`.

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
  needs `Read first: <areas>` naming at least the areas of the issue's labels (`docs/lessons/areas.toml`). A game's
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
  issue start` puts the rules of the issue's areas into the agent's context (gdstudio #99,
  [lesson](../lessons/2026-11-02-docs-written-on-a-branch-were-left-for-a-batch.md))).

## Agent stalls {#stall}

A background task agent whose turn ends is finished for good: nothing wakes it, `ListAgents` still says `running`, and
nothing shows on GitHub. It happened three times on 2026-11-02 (the agents ended on "Now the autopilot." and the like;
[lesson](../lessons/2026-11-02-an-agent-that-ended-its-turn-on-a-next-step-stalled.md)). The rule in the agent
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

Both registrations already exist (`.claude/settings.json`; the game template's `launch.py` runs the same dispatcher),
so a game gets the gate with `gds sync`; restart sessions to pick it up.

## Proof {#proof}

At Stop, a session that changed visual files of a game (scenes, shaders, `game/ui/`, `game/assets/`, `game/world/`)
is held back once until a capture newer than those changes sits in `<workspace>/scratch/<repo>/<branch>/`. The reason
names the folder and the Movie Maker command.

## Session start

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
  the hook above pulls after a merge command, at session start and at Stop
  ([lesson](../lessons/2026-11-02-local-main-fell-behind-the-merges.md))).

## Finished worktrees {#sweep}

`gds worktree sweep` ([the rules](workspace.md#sweep)) is started in the background at session start, right after a
shell command that merges a pull request, and at Stop, at most once every ten minutes (`[sweep]` in `hooks.toml`). The
hook only starts the process and returns, so it never blocks or delays a session; the sweep takes a lock file
(`cache/worktree-sweep.lock`, taken over after half an hour), so sessions that start together run one sweep, and it stops
by itself after 20 minutes. Its report is appended to `scratch/worktree-sweep.log`. On Windows the process is started
with `CREATE_NO_WINDOW`, so neither it nor its git children flash a console window
([lesson](../lessons/2026-11-03-expired-monitors-left-their-polling-loops-running.md)). `enabled = false` turns it off and
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
| `SubagentStart` | Tells every project agent the same, adds the sections closest to its issue and the rules of its areas ([above](#docs)), and says that an agent whose task came from a correction puts the log line in its final report: the coordinator publishes it, so many agents never edit one page. Read-only helpers (`[agents] helpers`) get nothing. |
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

## Tests

`python/tests/test_hooks.py` covers every guard (the comment guard with one case per route, spelling and mutation, and
one per command that must keep working), the answer protocol, the fail-open path, the issue-order checks, the
stall gate (reports, blockers, the refusal limit, the reviewer), the idle-issue check (the refusal and both commands,
a task agent never judged, the refusal limit and its reset, the `gh` cache, failing open) and the learning loop (each
event's text, the queue gate and its loop guard, and the dispatcher run as a process) and the background sweep (started
once, throttled, switched off, log moved aside; started by session start, a merge and Stop).
`python/tests/test_sweep.py` covers `gds worktree sweep` on real git repositories.
`python/tests/test_issues.py` covers the window, `gds issue` (including `block`, `unblock` and the parsing of the
`Blocked (...)` line) against `gh` JSON recorded in `python/tests/fixtures/`.
