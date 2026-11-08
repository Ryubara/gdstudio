---
areas: [audio, tools]
---
# An `--only` flag by name rendered another folder's sound

2026-11-03

- **Saw:** after rendering the menu's new `deny` sound with `generate.py --only ...,deny,...`, `git status` listed a
  changed `world/deny_1.ogg` that the task never meant to touch.
- **Cause:** `--only` matches the entry's name, not its folder; the shop's `deny` had the same name and was rendered
  too, from its own recipe, over the committed file.
- **Fix:** `git checkout` of the file, and the new sound is named for what it is (`refuse`); run `git status` after
  every render and look for files outside the folder you meant.
- **Docs:** [Godot: Audio, Menu sounds](../engines/godot/audio.md#menu-sounds).
