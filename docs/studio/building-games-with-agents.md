# Building games with agents

How GDStudio went from one prompt to a coordinator running a dozen agents on a game, in about a night, and what to
copy to do the same on another engine.

## Timeline {#timeline}

| Phase | What happened |
| --- | --- |
| 1. Brief | The user described how they work (agents write the code and the 3D assets) and a first game idea. |
| 2. Stack | Godot and Blender chosen; GdUnit4, Movie Maker captures and an autopilot as the proof tools. |
| 3. Workspace | A plain folder of separate repositories (kit, game, assets), modelled on Coney, built by a bootstrap. |
| 4. Pinned tools | Godot, Blender and ffmpeg pinned by version and hash in `tools.toml`, never a system copy. |
| 5. Conventions | Groundwork: one conventions file renders PR and issue templates and the CI checks for every repo. |
| 6. Guards | A hook dispatcher refuses unsafe actions (unpinned tools, protected merges, leaking secrets). |
| 7. Roster | Four broad agents (Godot, Blender, backend, reviewer) synced from the kit into each game. |
| 8. Game | Deadnight's design docs, then parallel agents on player, zombies, weapons, UI, audio, map and networking. |
| 9. Review loop | A reviewer agent checks each merged feature; findings become issues and new agents. |
| 10. Evidence rules | Screenshots, Issues affected, before/after captures and Failed first added after the fact. |
| 11. Live tests | A test server deployed to Railway to measure real latency, then torn down. |
| 12. Handoffs | Long sessions cleared and resumed from `HANDOFF.md`, written at each checkpoint. |

## What made it work {#what-made-it-work}

- **Proof, not claims.** Done means tests and captures pass; the agent looks at its own captures before asking.
- **Agents test everything.** Input simulation, bots and audio analysis replace "please try it" for the user.
- **A coordinator and specialists.** The main session plans, briefs, merges and reports; it does not write features.
- **One issue, one branch, one PR.** Each agent works in its own worktree and squash-merges with auto-merge on.
- **Rules as code.** Conventions are checked in CI and hooks refuse what must never happen, so a brief can stay short.
- **A separate reviewer.** It never edits; it reproduces numbers and files what it finds.
- **Learning in the topic pages.** A mistake sharpens the section an agent reads for that work (the approach, what to
  watch out for, where it was seen), found first with `gds learn`, so the docs improve instead of filling with one file
  per problem ([Learning in the topic pages](rules.md)). The first week wrote 963 lesson files, many on the same
  subject.

## What went wrong {#what-went-wrong}

- Hook refusals stopped legitimate merges until the user granted a time-boxed merge authorization.
- A relative worktree path landed inside a repository; worktrees now always take absolute paths.
- GitHub stamped records 45 to 60 minutes ahead; times are checked against the local clock.
- Agent definitions changed in the kit but not in the game; `gds sync` now follows every roster change.
- The maintainer caught many design gaps first (camera, HUD, art, numbers against the reference); see
  [What the maintainer caught](maintainer-corrections.md).
- Many gaps were never considered when the game was first built; the checklist for the next game is
  [What to plan from the start](plan-from-the-start.md).

## Reproduce it on another engine {#reproduce-it-on-another-engine}

Everything except the engine column is generic and carries over unchanged.

| Piece | Godot (ours) | Unity | Unreal | Bevy |
| --- | --- | --- | --- | --- |
| Pinned editor | `tools.toml` + `gds tool path` | Editor version + hash | Engine build + hash | `rust-toolchain.toml`, `Cargo.lock` |
| Headless run | `--headless` | `-batchmode -nographics` | `UnrealEditor-Cmd -nullrhi` | `MinimalPlugins` app |
| Tests | GdUnit4 | Unity Test Framework | Automation / Gauntlet | `cargo test` on a headless `App` |
| Captures | Movie Maker + `gds capture` | Recorder package | Movie Render Queue | Screenshot plugin + ffmpeg |
| Assets | Blender, glTF | Blender, FBX/glTF | Blender, FBX | Blender, glTF |
| Agents | `godot-engineer` | rename and rewrite the engine half of the brief | same | same |

Steps, in order: pin the tools; make the workspace and bootstrap; write the conventions and render them; add the hooks;
define the roster with proof steps in each brief; write the game's design docs; then dispatch agents in parallel and
review every merge.

## Limits {#limits}

- Some steps stay with the user: maintainer decisions, licences, accounts (a Discord application), and paid assets.
- A coordinator can track about a dozen agents at once; beyond that, results queue faster than they can be reviewed.
