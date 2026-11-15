# Issue order, idle issues and agent stalls

<!-- new section: moved from hooks.md#issues, #idle and #stall, which had under 300 bytes left of its 50 KB
limit (gdstudio #1561) -->

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
   While the kit has more open pull requests than `merge.queue_cap` (`.github/conventions.yml`; 0, so any open one),
   nothing is idle: the landing freeze ([Starting work](starting-work.md#parallel)). The kit is read first, so no game
   is asked then.
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
   a hand-written block its issue body does not back) of each blocked issue, and lifts those whose blockers all closed
   (a pull request merged or closed counts), so a block cannot outlive its cause. A block on the maintainer, on an issue
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

## Agent stalls {#stall}

A background task agent whose turn ends is finished for good: nothing wakes it, `ListAgents` still says `running`, and
nothing shows on GitHub. It happened three times on 2026-11-02 (the agents ended on "Now the autopilot." and the like;
[Agents](agents.md#the-loop)). The rule in the agent
definitions did not stop the third, so `SubagentStop` now refuses such an end. Settings: `[stop_check]` in `hooks.toml`.

1. Only the agent types in `[stop_check] agents` are judged: `godot-engineer`, `backend-engineer`, `blender-artist`,
   `level-designer`. The `reviewer`, the helpers and every other type are never touched.
2. The agent's last message (`last_assistant_message`, else the end of its transcript) is a **report** when it matches
   `[stop_check] report`: a pull request link (`github.com/.../pull/N`) or `PR #N` / `pull request #N`; a `Mistakes`
   heading or label (every report has one, [Docs ship with the change](hooks.md#docs)); a line that starts `Blocked:` or
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
