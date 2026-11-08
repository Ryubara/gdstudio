---
areas: [process, godot-ui]
---
# A stopgap "until #391" stayed after #391 closed

2026-11-02

- **Saw:** Play together and Quick join did the same thing; Quick join should skip that screen and join the first
  game found (Deadnight #526).
- **Cause:** `main_menu.gd` sent `quick_join` to the Play together screen "until the rooms flow (#391) replaces" it.
  #391 closed and nobody looked for the note, so the menu's Quick join was a second Play together.
- **Fix:** Deadnight #526 routes Quick join straight into the first open night.
- **General:** before closing an issue, grep the code and docs for its number and resolve every "until #N" note in the
  same pull request. Two buttons with different labels do different things, and a test per route proves it.
- **Docs:** [What the maintainer caught](../studio/maintainer-corrections.md).
