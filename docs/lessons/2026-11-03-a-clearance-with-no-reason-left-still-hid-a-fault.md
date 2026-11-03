---
areas: [gameplay, tests]
---
# A rule whose reason was gone still hid a fault: measure before removing it

2026-11-03

- **Saw:** the maintainer made a grenade hurt only its thrower (Deadnight #856), which left the bots' 7.5 m
  clearance from every teammate protecting nobody. Removing it doubled the throws per night (18 to 42 over six 120 s
  nights), and the bots hit themselves: 12 of 42 blasts touched the thrower, and the committed soak failed on its
  own seeds.
- **Cause:** the clearance also kept the throws to packs far from the group the bots follow, which hid two faults of
  the bots' own (a bot walks toward its live blast in the 3 s fuse; a zombie stops a grenade short). A second slip
  in the same task: a test that "the person takes nothing" read the person's health in a pack of chasers, and the
  dead took it.
- **Fix:** keep the rule, state in the code and the design page that it no longer protects health, and open an issue
  to fix the faults first, then remove it. Take a before and after of the old and new arm with the same instrument
  (the soak read the thrower's own distance from the body), on the same seeds, in a separate checkout of `main` for
  the "before". Assert "nothing says a grenade touched them" (no `player_blasted`, no grenade `player_hurt`), never
  a health value another source can change.
- **Docs:** `docs/research/grenades.md` in Deadnight, "Only the thrower (#856)".
