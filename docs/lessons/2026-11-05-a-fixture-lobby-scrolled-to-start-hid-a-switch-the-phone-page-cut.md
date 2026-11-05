---
areas: [godot-ui, web, tests]
---
# A fixture lobby that scrolled to Start hid a switch the phone page cut off

2026-11-05

- **Saw:** the host's Private switch (Deadnight #1186) was tested and captured at a phone's canvas with a fake backend
  and was on screen with Start. On a real 844 x 390 page in Chromium (`phone_layout.py --section lobby`) the lobby came
  up scrolled to the end of its area, the switch half out of the top, and a finger tap at the spot the page named hit
  the panel's frame.
- **Cause:** the screen opens scrolled to Start (`follow_focus`). In a suite the scroll stopped with Start at the bottom
  of the area; on the page the copy buttons and the Server Browser button sit under Start and the scroll ended further
  down. The fixture and the page lay out the same screen and scroll it differently, so a fit check passed on rows the
  player could not see.
- **Fix:** `LobbyPrivateSwitch.reveal` scrolls back to the row after the focus has moved the scroll, when Start still
  fits under it. A test scrolls to the end and asserts the switch and Start are both inside the scroll's rectangle; the
  probe names the switch (`spots`, `lobby_private`) and the script taps it with a finger and reads what the stand-in
  backend was told.
- **Check for next time:** a control meant to be on screen with another one is checked on the real page, by its position
  in the viewport and by a tap, not by "the row is visible" in a fixture; when a screen scrolls to a focused control,
  scroll the test's area to the end as well and check what is left in view.
- **Docs:** the game's `docs/research/phone-page-scale.md`, "The host's lobby on a page".
