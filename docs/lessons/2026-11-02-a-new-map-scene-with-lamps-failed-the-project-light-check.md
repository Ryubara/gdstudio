---
areas: [tests, godot]
---
# A new map scene with lamps failed the project's light check

2026-11-02

- **Saw:** CI failed a suite the change never touched: `<new map>.tscn has a light: add it to LIGHT_SCENES`
  (Deadnight `tests/world/test_lot_light_cap.gd`), and the map's moon was the open lot's 0.36.
- **Cause:** the second map's builder reused the lot's generator, which writes lamps and the outdoor moon, and only
  the new map's own test folder was run locally; the light-cap suite walks every scene in the project.
- **Fix:** list the scene in `LIGHT_SCENES` with a suite of its own that counts its lamps per mesh against the cap
  less the fight's headroom, set the indoor moon to 0.1, and run the whole `tests/world` folder before pushing.
- **Docs:** [Lighting in Compatibility](../engines/godot/compat-lighting.md#light-cards-indoors-moon-shafts-door-glow-chalk).
