# ResourceSaver leaves default values out of a .tres

2026-11-01

- **Saw:** a tuning resource saved from a script showed almost no values in the `.tres`.
- **Cause:** `ResourceSaver` omits every property equal to the script's default, so the file hides the tuning.
- **Fix:** write every value back explicitly with a short script (or change the defaults), so designers see each number.
- **Docs:** Deadnight `docs/research/rules-engine.md`.
