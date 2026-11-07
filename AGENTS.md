# AGENTS.md -- GDStudio kit

GDStudio makes games with Godot and Blender, built by agents. This repository is the **kit**: the tooling, rules,
pipelines and global docs that every GDStudio game shares. Each game is its own repository beside this one.

## Layout

The workspace is a plain folder (never a repository) that `bootstrap.ps1` / `bootstrap.sh` builds
(`docs/workspace.md`):

```text
<workspace>/
  repos/gdstudio/            this kit; repos/<game>/ every game; repos/gdstudio-assets/ the shared asset library
  worktrees/<repo>/<branch>/ every git worktree, and nowhere else
  scratch/                   task output, captures, reports, PR text; never committed
  cache/  tools/             downloads; pinned Godot and Blender (tools.toml)
  refs/   vault/             reference material and licensed-but-not-redistributable assets; never committed
```

In this repo: `python/` the `gds` CLI (uv), `tools.toml` pinned tools, `workspace.toml` folders and repositories,
`docs/` the global docs hub.

## Rules (never broken)

- **Pinned tools only.** Run Godot and Blender through `gds tool path godot|blender`, never a Steam or system copy.
  Changing a version is a pull request to `tools.toml` with the vendor's hashes.
- **Public repositories.** Nothing whose licence forbids redistribution is committed: paid asset packs live in
  `<workspace>/vault/`, reference images in `<workspace>/refs/`. Every third-party file that is committed has a
  licence entry (the licence gate, coming with the hooks).
- **Original work.** GDStudio games are original. Other games are studied for design and used as visual reference;
  their content, layouts, names and assets are never copied.
- **Proof, not claims.** Work is done when its tests and scenario captures pass, not when it looks done.
- **Learn in the same session.** When the maintainer corrects an agent or reports a problem in earlier work, the
  learning is written into the docs in that session: a row on `docs/research/maintainer-corrections.md`, and a lesson
  (`docs/lessons/`) when the cause is general. Agents read the checks that touch their task before they start. The
  hooks enforce it (`docs/hooks.md#learning`).
- **No comments under the maintainer's account.** Nothing an agent or a tool runs posts a comment or a review on an
  issue or a pull request under the maintainer's GitHub account, ever, with no exception: labels say that work is under
  way, and a report goes in the pull request's body or the scratch folder (`docs/hooks.md#comments`).
<!-- conventions:begin maintainer-decisions -->
- **Maintainer decisions** are never an agent's: it stops and reports instead of acting. They are: make an existing
  repository public or private (a new game's, from `gds new game`, is not one: kit #779); tag a release; force-push
  the default branch or someone else's branch; legal or licence questions, an existing repository's licence among
  them (a new game's MIT is not one); change these conventions; change a pinned tool version (tools.toml); commit a
  third-party asset or its licence entry.
<!-- conventions:end -->

## Build and test

- Python: `uv run --project python pytest`; `uv run --project python ruff check python` and `ruff format --check`.
- Workspace: `uv run --project python gds doctor`.
- Windowed Godot (captures, autopilots, GdUnit without `--headless`):
  `uv run --project python gds godot -- <godot arguments>`, never the Godot program directly: a plain window takes the
  keyboard from the person at the machine (`docs/godot/no-focus.md`).
- Local browser probes (Playwright, a game's `tools/web_smoke/*.py`) and any other program that can take the mouse:
  `uv run --project python gds quiet -- <command>`: headless Chrome under pointer lock traps the person's cursor.
- Before committing: `uvx pre-commit run --all-files` (installed once with `uvx pre-commit install`).
- Docs: `uvx --with-requirements requirements-docs.txt mkdocs build --strict`.
- Start work: only `uv run --project python gds issue start <owner/repo>#N --agent <name>` (the oldest ready issues first,
  `P-critical` before them; `gds issue list` shows them); a task agent's prompt carries `Issue: <owner/repo>#N` or
  `PR: <owner/repo>#N` (`docs/starting-work.md`). Nobody sets `S-in-progress` by hand; only the maintainer sets `P-critical`.
- Lessons: a lesson has `areas: [...]` front matter; `docs/research/mistakes-by-area.md` is built from the lessons by the
  docs build and `gds lessons <area>`, never committed (`python .github/scripts/mistakes.py check` fails on a lesson
  without areas). The agent that finds a
  mistake writes the lesson and opens the kit pull request in the same task (`docs/hooks.md#docs`). A `Fix` or `Rework`
  pull request, or one after a failed check or closing a `bug` issue, carries `Lessons: docs/lessons/<file>.md`; one
  that closes an issue carries `Read first: <areas>`.

## Commits and pull requests

Every rule a program checks is a key of `.github/conventions.yml`, the one source. The blocks below are generated
from it (`uv run --with pyyaml python .github/scripts/groundwork.py render`): edit the file, not the block.

<!-- conventions:begin commit-rules -->
- Title `area: Verb the rest`, at most 72 characters, present tense, no trailing period. Verbs: Add, Fix, Update,
  Remove, Rebuild, Rework, Improve, Document. Areas: `build`, `ci`, `workspace`, `tools`, `hooks`, `agents`,
  `godot`, `blender`, `audio`, `docs`, `tests`. A breaking change ends the title with `(BREAKING)`.
- An agent ends the message with `Co-Authored-By: <model name> <noreply address>` (one of: `noreply@anthropic.com`,
  `noreply@google.com`, `noreply@openai.com`) and no other trailer. No other e-mail address appears in a message.
<!-- conventions:end -->

A pull request the maintainer must see first carries `S-hold` (`gds pr hold <owner/repo>#N`): a required check stops
every merge while it is on, and only the maintainer takes it off, by hand (`docs/hooks.md#hold`).

Work happens on branches, one pull request per change, squash-merged; `main` takes no direct pushes. A pull request
description follows `.github/pull_request_template.md`.

<!-- conventions:begin manual-paths -->
- A pull request that changes any of these is merged by a maintainer by hand, never by auto-merge:
  `.github/conventions.yml`, `AGENTS.md`, `.claude/settings.json`, `.claude/hooks/`, `tools.toml`.
<!-- conventions:end -->
