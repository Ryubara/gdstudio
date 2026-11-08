---
areas: [tests, web]
---
# A new prompt hung every test and browser smoke that passed through the flow

2026-11-02

- **Saw:** Deadnight #485 made the first Play together ask a player with no name for one. Two existing GdUnit tests
  (a night found by a link, a link to a night that is gone) then each waited about 5 minutes and timed out, because
  they entered the flow with no saved name and nothing answered the prompt. The browser smoke `rooms.py` would have
  hung the same way in CI: its four pages press Quick join, Create a night and open `?room=CODE` with no name.
- **Cause:** a prompt that waits for the player is a new state in a flow that used to run straight through. Every
  automated path through the flow (unit tests that call the screen, and browser smokes that drive it) arrives with a
  fresh profile, so each one now stops at the prompt. The change was tested through its own new tests only.
- **Fix:** before adding a prompt or a wait to a flow, search for everything that enters it (`grep` the screen's class
  name, its route and its URL parameters in `tests/` and `tools/web_smoke/`) and update each one in the same change.
  A unit test gives the player the state that skips the prompt (a saved name) and restores the old profile; one new
  test answers the prompt. A browser smoke answers the real prompt, which also proves it in a browser: the probe
  publishes a flag for it (`naming`) and the smoke types into the field when the flag is up.
- **Docs:** [Web export](../engines/godot/web-export.md).
