# Agents

A small roster of broad agents, each with its own instructions and the hooks' rules. No `general-purpose` agent: it
has neither (the hooks refuse it). Every agent researches as part of its own work; there is no research agent.

| Agent | Model | Covers |
| --- | --- | --- |
| Coordinator (the main session) | Opus 5.5, medium | plans, writes issues, briefs and starts agents, merges, talks to the maintainer |
| `godot-engineer` | Sonnet 5.5, high | GDScript, scenes, UI and motion, gameplay, networking, shaders, tests, captures |
| `blender-artist` | Opus 5.5, high | modelling, decimation, rigging, animation, retexturing, variants, weapons, import to Godot |
| `level-designer` | Opus 5.5, high | map layout and review: loops, sightlines, spawns, pacing, landmarks, light, reach, escape and roost sweeps, phone reading ([principles](research/level-design.md)) |
| `backend-engineer` | Sonnet 5.5, high | platform backend (sign-in, lobbies, matchmaking, saves), game-server deployment |
| `reviewer` | Sonnet 5.5, high | reviews a pull request it did not write: code, docs, assets, captures; never edits |

Definitions: `.claude/agents/*.md`. A new agent is added only when a kind of work keeps recurring that none of these
covers well.

## The loop

1. The coordinator writes an issue (problem first, what "done" means) and starts the right agent on it. Two issues
   that need the same mechanic are never given to two agents at once: one owns it, the other waits on it, and each brief
   names the open pull requests and files to stay out of
   ([lesson](lessons/2026-11-02-the-coordinator-gave-one-mechanic-to-two-agents.md)).
2. The agent works in `<workspace>/worktrees/<repo>/<branch>/`, researching as it goes and writing what the next
   person needs into the game's `docs/research/`.
3. It proves the work: headless Godot with no errors, and for anything visible, captures it has looked at, in
   `<workspace>/scratch/<repo>/<branch>/`.
4. It opens the pull request with the captures attached and auto-merge on (off for manual paths). Closing and
   reopening it (for a fresh CI run) turns auto-merge off: turn it on again in the same command
   ([lesson](lessons/2026-11-02-closing-and-reopening-a-pull-request-turned-auto-merge-off.md)). A workflow change on
   main (a job's time limit) reaches a pull request only when main is merged into its branch
   ([lesson](lessons/2026-11-02-a-pull-request-ran-ci-with-its-branchs-old-time-limit.md)).
5. The `reviewer` posts a verdict; findings become fixes on the branch or new issues.
6. While the pull request is open, the `pr-status` workflow labels it `S-conflict` when it conflicts with its base and
   `S-ci-failing` when a required check failed on its latest commit. An agent that sees one fixes it forward on the
   branch (rebase, or fix the check); the label clears by itself ([Contributing](https://github.com/Ryubara/gdstudio/blob/main/CONTRIBUTING.md#pull-request-labels)).
7. A running agent can be stuck with nothing on GitHub to show it: an agent that ends its turn by announcing its next
   step stops there. The coordinator checks each running agent's newest worktree and scratch file time; an hour with
   no change is a stall, and a fresh agent takes over from its notes
   ([lesson](lessons/2026-11-02-an-agent-that-ended-its-turn-on-a-next-step-stalled.md)). The `SubagentStop` hook also
   refuses the end of an engineer or artist whose last message is no report ([Agent stalls](hooks.md#stall)).

<!-- hold proof t0 -->
