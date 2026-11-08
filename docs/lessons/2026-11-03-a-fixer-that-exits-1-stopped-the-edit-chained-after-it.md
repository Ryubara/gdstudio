---
areas: [tools, tests]
---
# A fixer that exits 1 after fixing stopped the edit chained after it

2026-11-03

- **Saw:** Deadnight's `test_weapon_muzzle.gd` failed with `m249 is in neither FIREARMS nor NOT_FIREARMS` right after a
  command that "added" the three new ids to that list; the list was unchanged.
- **Cause:** the command was `python tools/check_texture_imports.py --fix <files> && python - <<EOF ... EOF`. The
  checker exits 1 when it had something to fix (so the pre-commit hook stops the commit), which `&&` read as a failure,
  so the edit after it never ran; its printed list of fixed files looked like success.
- **Fix:** run a fixer on its own line (or end it with `; true`) and run the next step separately; read the file or
  `git diff --stat` after an edit made from the shell.
- **Docs:** [Weapons in the Toon Shooter style](../tools/blender/weapons.md#many-weapons-in-parallel); the earlier
  [chain lesson](2026-11-02-a-commit-piped-to-tail-hid-a-failed-hook.md) is the same family.
