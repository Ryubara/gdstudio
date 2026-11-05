---
areas: [godot-ui, tests]
---
# A note drawn inside a ticket button ran into the button's title, and the fit sweep passed

2026-11-05

- **Saw:** the Play tab's new start, *Server browser*, had the note *Join a night waiting or under way* drawn at the right
  of the ticket; the two texts overprinted. The whole `tests/ui` folder, including `test_ui_fit.gd`, was green; the
  overprint showed only in the capture of the menu (the first look at it, after the suites had passed).
- **Cause:** `MenuItemButton` draws its title and note itself with `draw_string`, so the fit sweep, which reads the rects
  of controls, has nothing to measure; a new title and note are only checked by eye.
- **Fix:** shorten the note, and a test measures the title and the note with the same fonts and sizes the button draws
  and holds their sum (with a gap) inside the room the button leaves
  (`test_no_start_of_the_play_tab_writes_its_note_over_its_title`). Look at the capture of every screen whose copy
  changed, whichever suites pass.
- **Docs:** none beyond this lesson.
