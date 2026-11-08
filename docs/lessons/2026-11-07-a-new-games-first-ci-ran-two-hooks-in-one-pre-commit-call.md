---
areas: [ci, tools]
---
# A new game's first CI passed two hook ids to one pre-commit call

2026-11-07

- **Saw:** the first game `gds new game` published (kit #779) had a red first `ci` run. Its `gdlint` job died in a
  second with `pre-commit: error: unrecognized arguments: gdlint`, and `build-ok` failed with it.
- **Cause:** the template's `ci.yml` (kit #778) ran `uvx "$PRE_COMMIT" run gdformat gdlint --all-files`, but
  `pre-commit run` takes one hook id. The kit's `template` job makes a game and runs every hook with
  `pre-commit run --all-files`. It never runs the game's own command lines, so nothing ran this one until a real
  repository did.
- **Fix:** one call for each hook. A test reads every `"$PRE_COMMIT" run` line of the template's workflows and fails
  on more than one hook id (it failed on the old line). The next probe's first CI run was green.
- **Check:** a workflow written for games is proven by a run in a real game repository, not by the kit's job that
  copies its steps. Make a throwaway game with `gds new game` and read its first CI run before calling a template
  change done.
- **Docs:** [A new game from a template](../godot/new-game.md).
