---
areas: [gameplay, tests]
---
# A weapon probe through the real damage path measured nothing until it reloaded and met the spawns

2026-11-04

- **Saw:** the first audit run of every weapon (Deadnight #972) printed "99 pulls, 40 s" for the revolver on round 15
  and for every gun on round 20, as if a pistol could not kill a walker, and a line-up of eight walkers in front of a
  .50 hit none of them though the shot was fired.
- **Cause:** two mistakes in the probe, not in the weapons. The loop fired only while the weapon said `fire_block() ==
  ""`, and an empty magazine says `empty`, which only a *fire* attempt turns into a reload, so a ten-round magazine
  ended every long kill at its tenth pull. And the combat server was made after the rules had spawned the zombies: it
  learns of a zombie from the rules' spawn event, so a server built later tracks none of them and every shot passes
  through the lot.
- **Fix:** the probe makes the server first, sends a reload when the weapon is empty and gives the weapon a reserve
  that cannot run out (rounds are a class target of their own, not a time to kill); a debug print of the event types
  (`shot_fired` with no `damage_dealt`) found the second one in one run. The probe is `tests/weapons/weapon_audit.gd`
  in Deadnight.
- **Check next time:** a probe that reports "never" is checked against its own loop before it is believed: print why
  the last step did nothing (blocked, empty, no target). Make every object that listens to events before the events
  happen, and assert in the probe that the first shot hit at all.
