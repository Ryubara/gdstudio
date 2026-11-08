---
areas: [tests, web]
---
# Each browser probe walked the menu its own way, and a menu rework broke two silently

2026-11-02

- **Saw:** after the menu rework (Deadnight #466), `pointer_lock.py` failed in #481's CI and `touch_look.py` failed
  against the live build; neither had been touched.
- **Cause:** every probe reached a night with its own key sequence through the menu, so a menu change broke each one
  separately, and only when that probe next ran.
- **Fix (Deadnight #484):** one shared start helper (`smoke.start_solo`) for every probe, and CI runs every probe's
  start-up, so a menu change fails there and not later.
- **General:** test drivers share one way into the game; a UI change then breaks one helper, at once, in CI.
- **Docs:** [What the maintainer caught](../studio/maintainer-corrections.md#done-wrong-first-caught-by-our-own-checks).
