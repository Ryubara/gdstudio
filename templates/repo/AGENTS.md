# AGENTS.md -- {GAME_TITLE}

{GAME_DESCRIPTION}

Godot 4.7 (GDScript), made with the GDStudio kit (`../gdstudio`), whose rules apply here too. It started from the
kit's `{TEMPLATE}` template (`gds new game`).

## Layout

`game/` the Godot project, laid out by feature: `core/` autoloads and foundations, `gameplay/<feature>/`, `ui/`,
`world/` maps, levels and lighting, `net/` only when the game is multiplayer, `assets/<domain>/<subject>/`, `tests/`
and `tools/` (captures and probes, left out of the export). `docs/` this game's docs site (`design/` what the game
is, `research/` what we learned building it). The folder, naming and dependency rules, and the check that enforces
them, are the kit's `docs/engines/godot/project-conventions.md`. Workspace folders (`scratch/`, `refs/`, `vault/`, `tools/`)
sit beside the repositories: `docs/` of the kit.

## Build and test

- Godot (pinned, never a Steam copy): `$(uv run --project ../gdstudio/python gds tool path godot)`.
- Import and smoke run: `godot --headless --path game --import`, then `godot --headless --path game --quit-after 30`.
- Tests (GdUnit4, installed untracked by `gds workspace init`): `godot --headless --path game -s
  res://addons/gdUnit4/bin/GdUnitCmdTool.gd -a res://tests -rd <path outside the project, relative to game/> -c --ignoreHeadlessMode`.
- Layout check: `uv run --project ../gdstudio/python gds check layout game`.
- Before committing: `uvx pre-commit run --all-files` (installed once with `uvx pre-commit install`).
- Docs: `uvx --with-requirements requirements-docs.txt mkdocs build --strict`.

## Rules (never broken)

- **Compatibility renderer only.** The web build is WebGL2; a feature that needs Forward+ or Mobile is not used.
- **Original work.** Other games are studied for design and used as visual reference; their content, layouts, names
  and assets are never copied.
- **Every third-party asset has a licence entry**, and its credit reaches the Credits screen.
- **Proof, not claims.** Visual work carries screenshots or clips, attached to its pull request.
- **Docs stay short.** One page per subject, updated in place; link instead of repeating.
<!-- conventions:begin maintainer-decisions -->
- **Maintainer decisions** are never an agent's: it stops and reports instead of acting. They are: make the repository
  public; tag a release; force-push the default branch or someone else's branch; legal or licence questions; change
  these conventions; commit a third-party asset or its licence entry; change the game's licence.
<!-- conventions:end -->

## Commits and pull requests

Every rule a program checks is a key of `.github/conventions.yml`, the one source. The blocks below are generated
from it (`uv run --with pyyaml python .github/scripts/groundwork.py render`): edit the file, not the block.

<!-- conventions:begin commit-rules -->
- Title `area: Verb the rest`, at most 72 characters, present tense, no trailing period. Verbs: Add, Fix, Update,
  Remove, Rebuild, Rework, Improve, Document. Areas: `core`, `gameplay`, `ui`, `net`, `world`, `art`, `audio`,
  `build`, `ci`, `agents`, `docs`, `tests`. A breaking change ends the title with `(BREAKING)`.
- An agent ends the message with `Co-Authored-By: <model name> <noreply address>` (one of: `noreply@anthropic.com`,
  `noreply@google.com`, `noreply@openai.com`) and no other trailer. No other e-mail address appears in a message.
<!-- conventions:end -->

Work happens on branches, one pull request per change, squash-merged; `main` takes no direct pushes. A pull request
description follows `.github/pull_request_template.md`.

<!-- conventions:begin manual-paths -->
- A pull request that changes any of these is merged by a maintainer by hand, never by auto-merge:
  `.github/conventions.yml`, `AGENTS.md`, `.claude/settings.json`, `.claude/hooks/`.
<!-- conventions:end -->
