# Hooks

Claude Code hooks are the rules enforced *while* an agent works, before anything reaches git or GitHub. Every event
goes to one dispatcher, `.claude/hooks/dispatch.py`; a game runs the same one through its `.claude/hooks/launch.py`,
which finds the kit by the workspace marker. Settings: `.claude/hooks/hooks.toml` (a game may override keys in
`.claude/hooks.local.toml`).

## What it refuses

| Guard | Refuses | Instead |
| --- | --- | --- |
| Agents | `general-purpose`, or an Agent call with no type | a project agent (`.claude/agents/`) or a read-only helper |
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

`python/tests/test_hooks.py` covers every guard, the answer protocol, the fail-open path, the issue-order checks and the
learning loop (each event's text, the queue gate and its loop guard, and the dispatcher run as a process).
`python/tests/test_issues.py` covers the window and `gds issue` against `gh` JSON recorded in `python/tests/fixtures/`.
