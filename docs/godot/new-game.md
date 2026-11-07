# A new game from a template

```text
uv run --project <workspace>/repos/gdstudio/python gds new game <name> --template 3d-blank \
    [--title "My Game"] [--description "One line."] [--remote <url of an existing GitHub repository>]
```

`gds new game` makes `<workspace>/repos/<name>/` from one of the kit's templates and leaves a game that builds, tests
and exports. The name is the repository's: lowercase words joined by hyphens. Nothing leaves the machine: the command
never creates a GitHub repository, never pushes and never touches repository settings, because a repository's
visibility is a maintainer decision.

## What it does

1. **Copies the files.** `templates/repo/` (what every game repository has) and then the template's own folder: its
   `game/` becomes the Godot project and its `docs/` the docs site's pages. The placeholders `{GAME_TITLE}`,
   `{GAME_SLUG}`, `{GAME_DESCRIPTION}`, `{TEMPLATE}`, `{KIT_REPO}` and `{KIT_PAGES}` are filled in, line endings
   are made LF, and a placeholder the command does not know stops it. These files are the game's own from then on.
2. **Syncs.** The same call as `gds sync`: agent definitions, the hook launcher and its settings, the commit and pull
   request checker, the hold workflows and the message-check hooks, with the lock `.claude/gds-sync.json`
   ([Sync](../sync.md)). `.github/scripts/pr_status.py` is copied from the kit once.
3. **Sets up git.** `git init -b main`, `origin` when `--remote` is given, `git lfs install --local`, a first commit
   (`build: Add the 3D Blank starter`, no trailer: a command wrote it), and the three hooks of `.pre-commit-config.yaml`
   (`uvx pre-commit install`). A step whose program is missing is skipped with a line and listed at the end.
4. **Installs the pinned addons.** GdUnit4 and the Godot MCP addon go into `game/addons/` untracked, as
   `gds workspace init` does for every game ([Workspace](../workspace.md)), when they were fetched.
5. **Registers the game.** With `--remote`, `[repos.<name>]` is added to the kit's `workspace.toml`, so
   `gds workspace init` clones the game on the next machine. That is an edit in the kit checkout: commit it in a kit
   pull request.

The game then holds: `game/` (the project), `docs/` and `mkdocs.yml` (a docs site), `.github/` (the conventions, the
workflows `ci`, `pr`, `docs`, `hygiene`, `pr-status`, `ci-failure`, `issue-area`, `issue-status`, the generated
template and issue forms), `AGENTS.md`, `CLAUDE.md`, `CONTRIBUTING.md`, `README.md`, licence, code of conduct, security
policy and the lint and format configuration. The game's `ci` runs the same steps a person runs: the conventions and
`gds sync --check` and [`gds check layout`](project-conventions.md), the import, a run of the main scene, the tests,
the web export, `gdformat` and `gdlint`, the docs build, `markdownlint` and `actionlint`.

## What stays with the maintainer

- Create the GitHub repository, add it as `origin` and push `main`.
- In the repository's settings, set Pages' source to GitHub Actions, then run
  `python .github/scripts/groundwork.py labels --apply`, `settings --apply` and `ruleset --apply` in the game.
- Run `gh workflow run hold-sweep.yml` once the ruleset requires `hold` ([The hold](../hooks.md#hold)).
- Decide the game's licence: the file is the kit's MIT licence until then.

The command prints this list at its end.

## The templates

| Template | What it is | Status |
| --- | --- | --- |
| `3d-blank` | A lit prototype level, the folder layout and the web export, with no entities and no game scripts ([Prototype surfaces and daylight](prototype-surfaces.md)). | made |
| `3d-third-person`, `3d-first-person`, `3d-universal`, `3d-top-down`, `3d-vehicle` | Controllers and sample content on the same base, filed one at a time after the one before it is tested. | planned |

## Adding a template

A template is a folder `templates/<name>/` with:

- `template.toml`: `title`, `description`, `default_description` (the README line when `--description` is not given)
  and, for a template built on another, `extends = "<base>"`.
- `game/`: files for the game's `game/` folder.
- `docs/`: pages for the game's `docs/` folder (`design/index.md` is the template's own page).

`extends` makes the base's files go in first and the template's on top, so `3d-third-person` holds a controller and
what changes in `main.tscn`, not a copy of the level. The folders `game` and `repo` of `templates/` are not templates:
`templates/game/` is what `gds sync` writes into every game, `templates/repo/` the repository files of a new one.
Something every existing game must receive belongs in `templates/game/` (synced), something only a new game needs in
`templates/repo/` or a template (copied once).

CI makes a game from every template on each kit change, with the real Godot: it checks the sync, the conventions, the
layout, imports the project, runs its tests and exports it for the web (the `template` job of the kit's `ci.yml`).
`python/tests/test_new_game.py` checks the command's steps without Godot.
