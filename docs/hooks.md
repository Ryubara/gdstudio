# Hooks

Claude Code hooks are the rules enforced *while* an agent works, before anything reaches git or GitHub. Every event
goes to one dispatcher, `.claude/hooks/dispatch.py`; a game runs the same one through its `.claude/hooks/launch.py`,
which finds the kit by the workspace marker. Settings: `.claude/hooks/hooks.toml` (a game may override keys in
`.claude/hooks.local.toml`).

## What it refuses

| Guard | Refuses | Instead |
| --- | --- | --- |
| Agents | `general-purpose`, or an Agent call with no type | a project agent (`.claude/agents/`) or a read-only helper |
| Unpublished docs | an agent finishing, or a session stopping, while a branch of the kit's worktrees has commits and no pull request; an agent's report with a `Mistakes` section and no lesson file | push the branch and open its pull request; write the lesson (docs/hooks.md#docs) |
| Agent stalls | a task agent (`godot-engineer`, `backend-engineer`, `blender-artist`) finishing on a message that is not a report: no pull request link or number, no `Mistakes` section, no `Blocked:` line, and no background task running | do the announced step in the same turn, or end with the report or `Blocked: <why>` ([below](#stall)) |
| Issue order | a task agent whose prompt names no started issue (`Issue: owner/repo#N`) or open pull request (`PR: owner/repo#N`); `gh issue edit\|create --add-label S-in-progress`; `S-in-progress` on a pull request; `P-critical` from a session | `gds issue start <ref> --agent <name>` ([Starting work](starting-work.md)) |
| Git | commits or pushes on `main`; force pushes; `--no-verify` | a branch in a worktree, a pull request |
| Merge | `gh pr merge --admin`; merging a pull request that changes a manual path | let checks pass; report it to the maintainer |
| Tools | Godot or Blender from Steam or PATH | `gds tool path godot\|blender` |
| Windowed Godot | Godot started from a shell without `--headless`: its window takes the keyboard focus (docs/godot/no-focus.md) | `gds godot -- <arguments>` or `gds capture frames`; `--headless` when nothing is drawn |
| Godot audio | a Godot started with a real `--audio-driver` (not `Dummy`), or `gds godot --with-audio`: it plays through the speakers of the person at the machine (docs/godot/no-focus.md#sound) | drop the option: `gds godot` adds `--audio-driver Dummy`, `--headless` and Movie Maker force it |
| Browser probes | a `tools/web_smoke/*.py` script or a Playwright run (`playwright test`, `uv run --with playwright python x.py`) not wrapped in `gds quiet`: headless Chrome under pointer lock clips the person's cursor (docs/godot/no-focus.md) | `gds quiet -- <command>` |
| Kills | stopping Godot or Blender by name (`taskkill /IM`, `pkill`, `killall`, `Stop-Process -Name`): every agent's run dies | kill your own process by its PID |
| Secrets | printing a key-like variable; dumping the environment | test that it is set |
| Files | editing secrets, caches, git internals, pinned tools; generated files | edit the source (`conventions.yml`, then render) |

All reasons come back at once. A refusal is Claude Code's JSON answer with exit code 0; if the dispatcher itself
fails, the call is allowed and the error printed, so a broken guard never locks a session out.

## Commit messages before they leave the machine {#pre-push}

The `pre-commit` framework installs three git hooks (`default_install_hook_types` in `.pre-commit-config.yaml`), and
`gds issue start` checks them ([Starting work](starting-work.md#worktree)):

| Git hook | Runs | Judges |
| --- | --- | --- |
| `pre-commit` | formatting, lint, the generated files | the staged files |
| `commit-msg` | `groundwork.py check-title --commit-msg` and `check-message` | the message file git hands over, before git's cleanup |
| `pre-push` | `groundwork.py check-push` | every commit being pushed (`PRE_COMMIT_FROM_REF..TO_REF`), merges included, as stored |

One function, `commit_problems`, judges a message in all three places and in CI (`check-commits`). The only input
handling is `stored_message()`: the help text git adds in the editor (and the `--verbose` diff under the scissors line)
is not part of the commit, so it is removed; every other line counts, including `#` lines, because `-m`, `-F` and
`--no-edit` keep them. The `commit-msg` hook cannot see what git will do afterwards (a `--cleanup=strip -F` message with
`#` lines is judged as kept, the safe side), so `pre-push` is the check that matches CI. It refuses the push with the
commits and what is wrong, and the fix needs no force push because the commit is still local: `git commit --amend
--cleanup=strip -F <message file>` for the last commit, `git reset --soft <base>` and a new commit for an older one. A
branch deletion and an empty push pass. `--no-verify` is refused by the Git guard above.

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

## Docs ship with the change {#docs}

The learning loop above starts from a maintainer message. This part starts from the agents' own work: what they got
wrong is written down by the agent that found it, in the same task, and the next agent reads it before it starts.

- **Areas.** Every lesson has `areas: [net, web]` front matter; the names, the issue label to areas map and the
  placement keywords are in [`docs/lessons/areas.toml`](lessons/areas.toml). [Mistakes by area](research/mistakes-by-area.md)
  is built from the lessons and the corrections rows (a row that links a lesson takes its areas, any other is placed by
  keyword) and is **not a file in the repository**: the MkDocs build creates it (`.github/scripts/mkdocs_glossary.py`, a
  `hooks:` entry of `mkdocs.yml`), `gds lessons <area>` and the hook below build it in memory, and
  `python .github/scripts/mistakes.py render` prints it. It used to be committed, so every lesson pull request rewrote
  it and the second of two concurrent ones conflicted or went stale (#119); now a lesson pull request touches only its
  own file. A test (and the `mistakes-by-area` pre-commit hook) fails on a lesson with no area or one that cannot be
  built; `backfill` places the lessons that have none, by keyword, as a script.
- **Injected, not hoped for.** `gds issue start` maps the issue's labels to areas (`A-net` is net, web and backend; the
  `general` area is always there) and keeps them in the ledger. When the Agent guard lets a task agent start it leaves a
  note (`cache/subagent-pending.json`, ten minutes) with the areas of the `Issue:` line; `SubagentStart`, which does not
  see the prompt, takes the oldest note for that agent type and adds the newest `inject_limit` items of each area, as
  text, to the agent's context (built from the lessons when it starts). A `PR:`-only agent gets the `general` area.
  `gds lessons <area>` prints the same.
- **Unpublished docs.** At `Stop` and `SubagentStop`, a branch of a worktree under `<workspace>/worktrees/gdstudio/`
  with commits ahead of `origin/main` and no open or merged pull request (one `gh pr list` for the kit) holds the
  session back once, naming the branch. If GitHub cannot be asked, the hook lets go.
- **The report.** `SubagentStop` reads the agent's last message (`last_assistant_message`, else the end of its
  transcript). A non-empty `Mistakes` section (a heading, or `Mistakes:` / `**Mistakes**`; `none` is empty) must name a
  `docs/lessons/<file>.md` that exists in the kit checkout or one of its worktrees, or the agent is held back once.
  Helpers and the `reviewer` are exempt. Settings: `[docs]` in `hooks.toml`.

- **The pull request.** The `body` check of `pr.yml` judges the description with what GitHub knows
  (`groundwork.py pr-history` lists the watched checks that failed on an earlier commit and the issues the pull request
  closes with their labels). It counts as an agent correcting earlier work when its title verb is `Fix` or `Rework`,
  when a check of `pull_requests.lessons.history_checks` failed on an earlier commit of it, or when an issue it closes
  is labelled `bug` (the nearest signal to "a fix to an agent-caused issue"). Such a pull request needs
  `Lessons: docs/lessons/<file>.md` (or a corrections row) in Summary, and `Lessons: none (reason)` is refused for it;
  elsewhere the line is optional. A pull request that closes an issue needs `Read first: <areas>` naming at least the
  areas of the issue's labels (`docs/lessons/areas.toml`). A game's conventions add `Kit docs: <kit pull request>` (or
  `none (reason)`) for a `Fix`, a `Rework` or a `bug` issue (`pull_requests.kit_docs`, same script). If GitHub cannot be
  asked, the title alone is judged.
  Every `none (reason)` line (`Lessons`, `Kit docs`, `Failed first`, `Issues affected`, `Screenshots`, `Before`) takes the
  reason in parentheses with one full stop after it, and refuses any other text after the parenthesis.

What it cannot see: that the listed mistakes are all the agent's mistakes (the report is the agent's own), a lesson
file that exists but says nothing, and a correction that fails no check and carries no `Fix` title; a reviewer reads
both. A game takes the `pr-history` command and the three rules when its `.github/scripts/groundwork.py` and
`conventions.yml` are updated from the kit's, in a pull request of its own.

## Agent stalls {#stall}

A background task agent whose turn ends is finished for good: nothing wakes it, `ListAgents` still says `running`, and
nothing shows on GitHub. It happened three times on 2026-11-02 (the agents ended on "Now the autopilot." and the like;
[lesson](lessons/2026-11-02-an-agent-that-ended-its-turn-on-a-next-step-stalled.md)). The rule in the agent
definitions did not stop the third, so `SubagentStop` now refuses such an end. Settings: `[stop_check]` in `hooks.toml`.

1. Only the agent types in `[stop_check] agents` are judged: `godot-engineer`, `backend-engineer`, `blender-artist`.
   The `reviewer`, the helpers and every other type are never touched.
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
and to read the checks of the corrections page that touch its task (see [Learning](#learning)). It fires on `startup`,
`resume`, `clear` and `compact`.

## Local mains {#mains}

Every repository in `<workspace>/repos/` that has `main` checked out follows origin: the maintainer opens those
checkouts in the editor, so they show what has merged. `git pull --ff-only` runs right after a shell command that
merges a pull request (`gh pr merge`, `gh api .../pulls/<n>/merge`, a `PostToolUse` hook), at session start, and at
Stop at most once every two minutes (auto-merges land without a command). It never discards: a checkout whose local
changes are in the way, or one on another branch, is left alone and named in the session's context. Settings:
`[mains]` in `hooks.toml`.

## Learning {#learning}

What the maintainer corrects is written into the docs in the same session, so the next agent gets it right the first
time. Four hooks make it happen, all in the one dispatcher; their texts are the `[lessons]` keys of `hooks.toml`.

| Event | What it does |
| --- | --- |
| `UserPromptSubmit` | Adds a two-line reminder to every message in a GDStudio workspace: if this message corrects an agent or reports a problem in earlier work, add a row to [the corrections page](research/maintainer-corrections.md) (the maintainer's words, concept missed, detail missed, check for next time) and a [lesson](lessons/index.md) if the cause is general, in a kit pull request in this session. If the cause is not known yet, queue the row. |
| `SessionStart` | Tells the session to read the checks that touch its task and to search the lessons index before solving. |
| `SubagentStart` | Tells every project agent the same, and that an agent whose task came from a correction puts the row's text in its final report: the coordinator publishes it, so many agents never edit one table. Read-only helpers (`[agents] helpers`) get nothing. |
| `Stop` | Holds the session back once while a queued row is unpublished (below). `stop_hook_active` lets the next stop through, so it never loops. |

**The queue.** A row whose cause is not known yet is a Markdown file in `<workspace>/scratch/kit-lessons-queue/`
(`[lessons] queue`, relative to the workspace): a title, the maintainer's words, and what is known. A file that
says `Waiting on: #N` (the issue that finds the cause) is left alone. When the cause is found, the row is published
in a kit pull request and its file moves to `published/`. The Stop gate lists every other file in the queue folder.
It applies to any session in the workspace; rows that are not yours: say so and finish.

Registered in `.claude/settings.json` and in the game template (`templates/game/.claude/settings.json`, which
`gds sync` writes into each game): restart sessions to pick the hooks up.

## Tests

`python/tests/test_hooks.py` covers every guard, the answer protocol, the fail-open path, the issue-order checks, the
stall gate (reports, blockers, the refusal limit, the reviewer) and the learning loop (each event's text, the queue
gate and its loop guard, and the dispatcher run as a process).
`python/tests/test_issues.py` covers the window and `gds issue` against `gh` JSON recorded in `python/tests/fixtures/`.
