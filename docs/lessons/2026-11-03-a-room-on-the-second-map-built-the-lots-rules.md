---
areas: [net, gameplay]
---
# A room on the second map played by the lot's rules table

2026-11-03

- **Saw:** the picker's second card, once shipped, started a room whose server threw errors at `use_offers.gd:20` (the
  door items were missing). Solo nights and the tests that built the map through `NightWorld` were fine.
- **Cause:** a map's rules overlay (`MapTuning`, laid over the shared table by `NightWorld.rules_for`) was applied by the
  solo night and `SeatedNight` only. `NightHost` (the room's server) and `Night.start_remote` (a client built from the
  WELCOME) built the map's scene but kept the shared table. A map that was never playable had never been through them.
- **Fix:** both lay `world.rules_for(table)` over the table before building the rules; `test_map_choice_net.gd` asserts
  the host's and the client's economy has the map's doors. When a map ships, play it through every path that builds a
  night (solo, host, client, balance simulator), not only the one the greybox tests use.
- **Docs:** [maps and the map choice](https://github.com/Ryubara/deadnight/blob/main/docs/design/maps.md).
