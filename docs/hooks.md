# Hooks

Claude Code hooks are the rules enforced *while* an agent works, before anything reaches git or GitHub. Every event
goes to one dispatcher, `.claude/hooks/dispatch.py`; a game runs the same one through its `.claude/hooks/launch.py`,
which finds the kit by the workspace marker. Settings: `.claude/hooks/hooks.toml` (a game may override keys in
`.claude/hooks.local.toml`).

## What it refuses

| Guard | Refuses | Instead |
| --- | --- | --- |
| Agents | `general-purpose`, or an Agent call with no type | a project agent (`.claude/agents/`) or a read-only helper |
| Git | commits or pushes on `main`; force pushes; `--no-verify` | a branch in a worktree, a pull request |
| Merge | `gh pr merge --admin`; merging a pull request that changes a manual path | let checks pass; report it to the maintainer |
| Tools | Godot or Blender from Steam or PATH | `gds tool path godot\|blender` |
| Secrets | printing a key-like variable; dumping the environment | test that it is set |
| Files | editing secrets, caches, git internals, pinned tools; generated files | edit the source (`conventions.yml`, then render) |

All reasons come back at once. A refusal is Claude Code's JSON answer with exit code 0; if the dispatcher itself
fails, the call is allowed and the error printed, so a broken guard never locks a session out.

## Proof {#proof}

At Stop, a session that changed visual files of a game (scenes, shaders, `game/ui/`, `game/assets/`, `game/world/`)
is held back once until a capture newer than those changes sits in `<workspace>/scratch/<repo>/<branch>/`. The reason
names the folder and the Movie Maker command.

## Session start

Each session is told its workspace, repository and branch, the pinned tool paths, and its branch's scratch folder.

## Tests

`python/tests/test_hooks.py` covers every guard, the answer protocol and the fail-open path.
