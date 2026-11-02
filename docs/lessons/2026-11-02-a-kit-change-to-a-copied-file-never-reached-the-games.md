---
areas: [tools, ci]
---
# A kit change to a file the games copy never reached the games

2026-11-02

- **Saw:** kit #152 fixed the commit message check and added a `pre-push` hook, and the games kept the old behaviour:
  the games' `groundwork.py` still dropped `#` lines and their `.pre-commit-config.yaml` had no `pre-push` hook, so a
  merge commit with a `# Conflicts:` paragraph could still reach CI there (Deadnight #503).
- **Cause:** `gds sync` had a list of what it copies (the agent definitions and `templates/game/`), and the files of a
  rule were not on it. The checker and the pre-commit hooks exist twice, in the kit and in each game, and nothing
  compared the copies. The pre-commit config is also half the game's own, which is why it was left out rather than
  copied whole.
- **Fix:** `gds sync` copies `.github/scripts/groundwork.py` and the marked blocks of `.pre-commit-config.yaml`
  (the kit's own config is their source), `--check` reports a game with the old copies, a game without the markers, or
  a kit hook defined twice ([Sync](../sync.md)).
- **General:** when a rule is enforced by a file that a game also carries, the file is on the sync list in the same pull
  request that changes the rule, and a file that is only partly the kit's gets marked blocks, not an exception. When
  you change a kit file, ask where else a copy of it lives: `grep` the games for its name.
