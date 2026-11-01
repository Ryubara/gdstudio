# Two scripts with the same class name broke the project after a merge

2026-11-01

- **Saw:** after merging `origin/main`, `PlayerState.new()` failed to parse with "Too few arguments for new() call.
  Expected at least 2 but received 0", and every test that loaded the player hung in the debugger.
- **Cause:** two branches had each added `class_name PlayerState` (the round rules' and the player controller's). Godot
  keeps one global class per name and silently picked the other branch's script.
- **Fix:** rename one (`PlayerMotionState`). Before naming a global class, run `grep -r "class_name <Name>" game`
  on `origin/main` as well as the branch, and prefer a name specific to the subject.
- **Docs:** [GDScript style](../godot/index.md).
