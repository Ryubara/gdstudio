---
areas: [godot, tests]
---
# A parse error in one script was reported on the files that use it

2026-11-03

- **Saw:** Deadnight #641. After a change to `bot_fight_brain.gd` the import printed `Could not parse global class
  "BotFightBrain" from "res://gameplay/bots/bot_fight_brain.gd"` and `Cannot infer the type of "fight" variable` in
  `bot_client.gd`, `Failed to compile depended scripts` in four more files, and nothing in the file that was wrong.
- **Cause:** a new method was named `_order`, the name of an existing member variable in the same class ("Function
  `_order` has the same name as a previously declared variable"). Godot reports the real error only when that script
  is loaded on its own; the users of its `class_name` get the generic one.
- **Fix:** `godot --headless --path game --check-only --script res://path/to/the_script.gd` prints the true message
  (and exits at once); the method got another name.
- **Check for next time:** on a "could not parse global class" error, run the check on the script it names before
  reading the files it points at; grep a class for the name before adding a function or a variable to it.
- **Docs:** [the Godot hub](../engines/godot/index.md), testing and capture table.
