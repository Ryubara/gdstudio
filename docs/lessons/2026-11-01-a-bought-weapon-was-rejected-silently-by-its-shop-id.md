# A bought weapon never reached the player because the shop's id is not the weapon's id

2026-11-01

- **Saw:** the rules sold `weapon_shotgun` and the crane's prizes, `purchase_made` carried the weapon, and the player
  never held it. No error: the combat server answered `unknown_weapon`, an event the night filters out.
- **Cause:** two vocabularies for one thing (`weapon_<id>` in the shop, `<id>` in the weapon catalogue) and a handler
  that passed one to the other. Nothing failed loudly, and no test asked who carries the weapon after a purchase.
- **Fix:** one translation (`WeaponCatalog.catalog_id`) used in the one place that hands over a purchase, and a test
  that buys through the rules and asks the combat server what is carried.
- **Docs:** [Weapon firing, Selling rounds](https://github.com/Ryubara/deadnight/blob/main/docs/research/weapon-firing.md).
