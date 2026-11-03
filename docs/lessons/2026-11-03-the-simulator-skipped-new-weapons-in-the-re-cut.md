---
areas: [gameplay, tests]
---
# The balance simulator never re-cut the new weapons because an allow-list did not name them

2026-11-03

- **Saw:** Deadnight #785: every "weapon bought, then re-cut" cell of nine draft weapons gave the revolver's re-cut
  result (mean round 12.4), whatever the weapon: the re-cut had gone to the revolver each time.
- **Cause:** `NightSim._re_cut_weapon` skips a weapon `UpgradeTuning.allows` does not list, and `UpgradeTuning.weapons`
  names the five old firearms by catalogue id. A new weapon is in the catalogue, the shop and the crane and still
  silently refused at the bench (and so in the model).
- **Fix:** when a roster grows, extend `UpgradeTuning.weapons` with it, and compare the re-cut cells with the revolver-only
  re-cut cell: identical numbers mean the list, not the weapon, decided. Also read `ammo` first: in the model a weapon's
  worth is mostly its reserve (an 80-round rifle and a 32-round shotgun run dry in a round), so fit magazine and reserve
  before the hit.
- **Docs:** [the re-cut plan](https://github.com/Ryubara/deadnight/blob/main/docs/design/upgrades.md#the-re-cut-plan-for-seventeen-weapons-785)
  (the Deadnight repository).
