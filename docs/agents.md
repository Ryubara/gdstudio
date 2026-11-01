# Agents

A small roster of broad agents, each with its own instructions and the hooks' rules. No `general-purpose` agent: it
has neither (the hooks refuse it). Every agent researches as part of its own work; there is no research agent.

| Agent | Model | Covers |
| --- | --- | --- |
| Coordinator (the main session) | Opus 5.5, medium | plans, writes issues, briefs and starts agents, merges, talks to the maintainer |
| `godot-engineer` | Sonnet 5.5, high | GDScript, scenes, UI and motion, gameplay, networking, shaders, tests, captures |
| `blender-artist` | Opus 5.5, high | modelling, decimation, rigging, animation, retexturing, variants, weapons, import to Godot |
| `backend-engineer` | Sonnet 5.5, high | platform backend (sign-in, lobbies, matchmaking, saves), game-server deployment |
| `reviewer` | Sonnet 5.5, high | reviews a pull request it did not write: code, docs, assets, captures; never edits |

Definitions: `.claude/agents/*.md`. A new agent is added only when a kind of work keeps recurring that none of these
covers well.

## The loop

1. The coordinator writes an issue (problem first, what "done" means) and starts the right agent on it.
2. The agent works in `<workspace>/worktrees/<repo>/<branch>/`, researching as it goes and writing what the next
   person needs into the game's `docs/research/`.
3. It proves the work: headless Godot with no errors, and for anything visible, captures it has looked at, in
   `<workspace>/scratch/<repo>/<branch>/`.
4. It opens the pull request with the captures attached and auto-merge on (off for manual paths).
5. The `reviewer` posts a verdict; findings become fixes on the branch or new issues.
