---
areas: [godot-ui, net]
---
# An online join hid the crosshair and never gave it back

2026-11-02

- **Saw:** the crosshair was missing on entering a game until the player pressed Esc and Resume (Deadnight #529). Every
  online join (Play together, Quick join, the Activity) started with no crosshair; a solo night was fine.
- **Cause:** the night screen's "Joining" card hid the reticle, the Tab scoreboard and the touch layer when it opened.
  A finished join only hid the card, and only Resume put the three back. It predates the report's suspect (#481): it
  failed the same on the commit before it and dates from Deadnight #313 and #336.
- **Fix (Deadnight #529):** one show and one hide function for each overlay, and every path that closes it calls the
  same restore; `test_night_crosshair.gd` joins over a real loopback socket and checks the first running frame.
- **General:** test a screen's first running frame through every route into it (solo, join, resume, the Activity), not
  only the route the author played. An overlay that hides HUD state has exactly one way to undo it.
- **Docs:** [What the maintainer caught](../studio/maintainer-corrections.md).
