---
areas: [gameplay, net, tests]
---
# A seat kept the weapons of the last player, and weapons never reached the next one's hands

2026-11-03

- **Saw:** the maintainer, in round 12 with three bots, found that some weapons taken from the prize crane never
  reached the player's inventory, likely the new ones (Deadnight #904). Every solo flow
  worked when walked: each of the 15 weapons from each wall and from the crane on both maps, with a free hand, full
  hands, the third-weapon perk, everything re-cut, and after a down that took the perk (rules, combat server, frame and
  HUD slots all agreed). Not one new weapon was missing from a table.
- **Cause:** two parts keep what a player carries: the rules' list (`PlayerState.weapons`) and the combat server's
  loadout, which is keyed by player id. A player who left was erased from the rules and never from the loadout, and the
  room gives the lowest free id to the next person. The newcomer carried the one before's weapons (re-cut, loaded,
  free) while the rules said the start weapon only, so the wall and the crane sold, refused ("already owned") and
  released by one list and gave by the other. Nothing in a solo night churns seats, so no solo walk could show it; it
  is also not the maintainer's solo desktop night, which stayed unexplained.
- **Fix:** the combat server forgets a player on the rules' `player_removed` (`CombatAction.forget_player`). The matrix
  test `test_weapon_sources.gd` reads each map's walls and crane pool from its tuning and walks every weapon through
  every carry, then walks a seat given up and taken again (it failed first: the newcomer carried `pistol, mp5`); the
  online twin runs the crane, the walls and the seat over a real socket.
- **Docs:** Deadnight `docs/design/weapons.md`, "Carrying weapons" (a seat is not a loadout). Check: state kept by
  player id in a second place (a combat loadout, a look, a bot's brain) is erased where the rules erase the player, and
  a test gives a seat up and takes it again; a "the thing did not arrive" report is walked from every source with the
  rules' list and the owner's own list compared side by side, and a source the walk cannot reach (here, seats that
  change) is named in the report as not covered.
