---
areas: [tests]
---
# A him-and-her capture pair ran with the same teammate

2026-11-02

- **Saw:** two runs of one capture tour, one as her and one as him, meant to compare the shoulder view, both showed two
  Carhops: the teammate preset was passed as the same number to both runs.
- **Cause:** the runs were one shell loop over a pair of arguments where only the player's preset was varied, and the
  teammate's argument was a literal.
- **Fix:** loop over full triples (name, player look, teammate look), print each run's looks in its log
  (`[female] loadout character: ...`), and read one picture of each run before comparing.
- **Docs:** [Testing and capture](../godot/index.md#testing-and-capture).
