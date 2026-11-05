---
areas: [godot-ui, input]
---
# A "no cut text" check asked for titles only, and a phone's Settings showed cut hints under mouse words

2026-11-05

- **Saw:** Deadnight's phone audit (#1275, fixed in #1290): on the real page (844 x 390 and 667 x 375 CSS px, ratio 2,
  touch mode) Settings showed "How faint the buttons are when your thumb i...", the value `1.00x` touching the
  scrollbar (0.0 units apart), and the phone's look sensitivity under "Mouse sensitivity" and "Push the mouse forward to
  look down". Every UI suite was green: `UIRow.title_cut()` existed and `test_phone_fold` asked it of the lobby and solo
  rules only.
- **Cause:** a check was written for the text that had failed (a row's title) on the screens that had failed. The row's
  other texts (the hint, the value) and the other screens (all five Settings tabs) were never asked, and nothing asked
  what words a touch device reads. The hint column is what the control leaves: 368 of a 960 unit canvas, because the
  control took 440.
- **Fix:** `UIRow.hint_cut()` and `test_settings_phone.gd` walk every tab on every `UiFitRun.PAGES` page; the phone's
  control is narrower and twelve hints have a shorter copy; the value keeps 16 units from the bar; a touch device's
  Settings has no Controls tab and its look rows say no mouse (a test scans their words). Check for next time: when a
  "text is cut" check is added, ask every text the row or card draws (title, hint, value, caption) on every tab and
  page, not the one that was reported, and give the check the real pages (`UiFitRun.PAGES`) so a phone is a phone. A
  screen shared with a desktop gets a test that its desktop words and widths come back after a phone-sized window.
- **Docs:** [Settings on a phone](https://github.com/Ryubara/deadnight/blob/main/docs/research/settings.md) in the game
  repository.
