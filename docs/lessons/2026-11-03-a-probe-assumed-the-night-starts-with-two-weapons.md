---
areas: [tests, godot-ui]
---
# A probe and a capture assumed two weapons at the start; the shipped night starts with one

2026-11-03

- **Saw:** the browser probe for the weapon slot keys waited for two carried weapons and timed out; the HUD captures
  taken with the test fixture (`RulesFixture.full_hands`: crowbar and pistol) never showed the usual start, one weapon
  and an empty second place.
- **Cause:** fixtures that fill the hands (written for the swap and carry tests) look like a night; the shipped
  `economy.start_weapons` is the pistol alone, and a browser cannot give itself a second weapon.
- **Fix:** capture and probe the shipped start first (`--solo` in the tour: the strip with an empty, dim second place),
  and keep the full-hands night for the picks. A probe waits for what the real night has, then branches on what it finds.
- **Docs:** Deadnight `tools/web_smoke/weapon_slots.py`, `docs/research/hud.md` ("Weapon slots").
