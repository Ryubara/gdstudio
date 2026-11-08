# Balance: the numbers a player meets

<!-- new section: no page held balance (hits to kill, prices, scores, the weapon roster); level design and audio
were the only gamedev pages -->

A number a player meets (hits to kill, a price, a score) is a design decision judged where the player meets it:
through the real attack in the real night, and on the card the player reads. A table, a unit test with a stub or the
balance simulator alone does not settle it. One game's own numbers live in that game's design pages.

## Shots to kill, through the real damage path {#shots-to-kill}

A weapon's damage, a zone's multiplier and a round's health can each be reasonable and still make a one-tap together.
Write the target first (how many hits a zone takes on a round), then measure the result through the real attack.

- **Approach:** Before tuning an attack, a zone multiplier or a health curve, print hits to kill per zone (head, body,
  limb) for rounds 1, 2, 5 and 10 through the real input, sweep, hit zones and damage path, compare them with a feel
  target on the design page, and keep the table in a test for every attack. **Watch out for:** numbers that were each
  reasonable made one-taps: a melee sweep that leaves the eye always met the head sphere (x1.5), and the start
  revolver's head hit of 60 topped the 50 and 58 health of rounds 1 and 2, with no shots-to-kill target written.
  **Seen:** Deadnight #897, 2026-11-03; Deadnight #898, 2026-11-03 (fix: deadnight `test_starter_pistol.gd` and
  `test_melee_hits_to_kill.gd`).

## A weapon is a model, a definition and a source {#roster}

A model is a weapon only when it has a definition (its numbers) and a source a player can reach (the start, a wall, a
drop). Art, definitions, the shop and the drops are one list.

- **Approach:** Keep art, definitions, the shop and the drops as one roster table (model, definition, source, numbers),
  with a test that every definition has a source a player can reach and every source names a real id; an unclear model
  is a question to the maintainer. **Watch out for:** there were 10 weapon models and 6 definitions; the bat and the
  fire axe had models and holds but no id, numbers or source, and the prize crane's pool was a hand-written list of
  four. **Seen:** Deadnight #461, 2026-11-02 (fix: every weapon got a definition and a source, Deadnight #530).
- **Approach:** When a roster, weapon or round number moves, grep the game for the old value and the type's id, change
  every copy in the same commit, and run the test folder of each file that names them. **Watch out for:** the bots kept
  the boss's health multiplier as a constant (13.0) after the tuning said 16.25, so they would have judged a revive
  against a boss a quarter weaker than the real one. **Seen:** Deadnight #688, 2026-11-03 (fix: the copy changed with
  the tuning; a bots test that compares its table with the game's caught it).

## Comparing weapons {#comparing}

"Weaker" and "stronger" are judged on more than one axis: damage per hit, ammunition and reload upkeep, range, reach.

- **Approach:** When a rule says "weaker" or "stronger", name every axis it is judged on (damage per hit, ammunition and
  reload upkeep, range, reach), and class a weapon of another kind by its kind (`WeaponDef.is_melee`), not by a row
  someone can add. **Watch out for:** the wall-tier rule ranked weapons on damage per hit alone, so the crowbar, bat and
  axe, which never run dry, landed in the lowest tier a wall may sell. **Seen:** Deadnight #910, 2026-11-03 (fix: a wall
  sells only weapons that cost upkeep).
- **Approach:** Match a retuned weapon on kills a second against the round's health (whole shots, overkill wasted),
  not on flat damage a second, and run the fast weapon-worth test before the long simulator run. **Watch out for:** a
  pump shotgun turned double-barrel kept its damage a second (129 against 127) and lost the weapon pick at round 10:
  a magazine of two is worth two kills a cycle however hard it hits, and a longer reload costs it all the more.
  **Seen:** Deadnight #700, 2026-11-03 (fix: 22 a pellet and a 1.8 s reload give the pump's kills a second).

## Prices the player reads {#prices}

A price or a count on a card is a rule the player reads and remembers. What the balance simulator's player does is set
in its policy, never by changing what a real player pays.

- **Approach:** Tame the balance simulator in the simulated player's policy, never in a price or a count the player
  reads; when a design departs from a reference value the maintainer knows (a genre price, a once-a-weapon rule), name
  the departure as a question in the issue. **Watch out for:** the re-cut bench cost 1,500 plus 1,500 per weapon already
  re-cut only because early simulator runs let a strong solo player re-cut four weapons a night, though the model had
  its own stopping rule. **Seen:** Deadnight #909, 2026-11-03 (fix: a re-cut costs 5,000, once a weapon).

## A score's smallest step {#denomination}

A score is a currency with a denomination: its smallest step is decided once, and everything is rounded to it in one
place.

- **Approach:** Fix a score's smallest step in the first design and round every award, price and loss to it in one place
  on the server after the last multiplier, with a test of seeded full nights that fails on anything off the step;
  rounding a tuning number is a retune, so the balance gate runs in the same pull request. **Watch out for:** points had
  no unit: tunings stepped by 1, a zombie type's multiplier rounded to whole points, each purchase rounded its own way,
  and the HUD showed sums like 31 to 34. **Seen:** Deadnight #916, 2026-11-03 (fix: `PointSteps` (award nearest, price
  up, loss down) in steps of 5).

## The balance gate and its samples {#gate}

<!-- new section: the balance gate (a test that holds the simulator's cells in ranges) and how big a sample must be
had no home -->

The balance gate is a test that runs the balance simulator over seeded nights and holds each cell (a skill level and a
team size) inside a range. A cell read from too few nights is a coin flip for the next change.

- **Approach:** Run the whole balance gate before a pull request that touches damage, health, a price, the shop, the
  crane or the carry, read a failure as which cell and by how much, take a baseline from a detached `origin/main`
  first, and when a cell the task did not name fails, say so in the pull request: a range or a curve is the
  maintainer's. **Watch out for:** a boss-health rise moved the average solo median; a faster-fire perk broke a brute's
  time to kill by 0.01 s; any new crane prize tipped a gate `main` passed at its edge; a "must fail" test of 20 nights
  had only a lucky margin. **Seen:** Deadnight #684, #687, #688, #789, 2026-11-03 (fix: ranges moved only on the
  maintainer's word; a test that expects a failure has several misses).
- **Approach:** Read a gap of two means at 300 nights before touching a threshold, and know a sample's noise floor: a
  curve distance between two samples has about 1.36 over the square root of the smaller one (0.48 at eight nights).
  Say in a report which sample each number came from. **Watch out for:** a gap of 60-night means moved by a few
  tenths with any change to the draws; eight bot nights cannot show a curve distance under 0.2. **Seen:** Deadnight
  #912, 2026-11-03; Deadnight (bot parity), 2026-11-03 (fix: 300-night reads; the 0.2 gate judged on the nightly's
  hundred nights).
- **Approach:** State a simulator lever as a multiplier on what it changes (blows that land times 0.97) rounded to the
  step a player sees, measure one lever at a time at about 400 nights a cell, and read the mean and the share past a
  round beside a median, which jumps a round at a boss wall. **Watch out for:** +0.05 of dodge was 25% fewer blows for
  the strong player and 11% for the middle one; a magazine rounded up gave a two-shell gun a third shell; one seed's
  solo median read 13 and 10 at 100 and 150 nights. **Seen:** Deadnight #687, #793, 2026-11-03; Deadnight
  (progression levers), 2026-11-04 (fix: levers as multipliers, a confidence beside every difference).

## A balance simulator {#simulator}

<!-- new section: the page's sections are about one number at a time; none covered a model that plays whole nights -->

A simulator plays many seeded nights with modelled players to show where a level's difficulty lands. It answers only as
well as its numbers and its players are the game's.

- **Approach:** Read every number a balance model uses from the game's own definitions and functions (the weapon
  catalogue, the damage model, the night's tuning, the generator's circuits), model only what the game does not own,
  drop what it does not do, and say in the report where each number comes from. **Watch out for:** numbers typed in
  beside the game's data passed the gate (an average solo player reached round 11) while the game's own weapons ended
  the same seeded nights at round 4: the stand-in rifle did 210 damage a second against 85, tonics had effects the game
  lacks, and lit ground slowed the dead without costing fuel. **Seen:** Deadnight, 2026-11-01 (fix: the model reads
  `WeaponCatalog`, `DamageModel` and `NightTuning`, and was retuned from the honest report).
- **Approach:** Give each simulated night its own player skill, drawn from the level's average with a spread (20 %),
  and measure difficulty by how close a round came to downing someone (the lowest health reached), not by damage
  taken. **Watch out for:** players of fixed skill on deterministic rules vary only by the enemy rolls, so every seed
  ended in the same round (100 % reached round 11, 0 % round 12), a cliff that says nothing about balance; damage taken
  is zero in most rounds and then everything. **Seen:** Deadnight, 2026-11-01 (fix: per-night skill with a spread,
  scored by the lowest health).
- **Approach:** Read every number a balance run or a fit starts from out of the data the game loads (the shipped tuning
  file, the curve's own function), never a script's defaults or a page's table, and have the unchanged baseline
  reproduce the gate's medians to the digit first. **Watch out for:** a sweep scaled a tuning script's `@export`
  defaults, not the shipped file, so "x1.0" was 20% more health and twice the step; nine weapons were fitted to a health
  table two retunes old (121 at round 10 against 140). **Seen:** Deadnight #745, #785, 2026-11-03 (fix: the tuning read
  through `RulesFixture.tuning()` and `RoundTuning.health_for`; the tables corrected).
- **Approach:** Register everything a player can reach when a balance run tries new content (the definition, its wall
  and crane rows, its ammunition on sale, the upgrade list), and compare with a control that defines it and leaves it
  out: identical numbers across variants mean a list decided, not the content. **Watch out for:** draft guns with no
  rounds on sale read two rounds low; an upgrade allow-list naming five old weapons gave every new weapon's upgrade cell
  the revolver's result. **Seen:** Deadnight #785, #793, 2026-11-03 (fix: the ammunition rows and the list extended).
- **Approach:** When the rules gain a limit or a state (a carry limit, a purchase that takes time), model it in the
  simulator's player in the same pull request and read what it does when refused; a rule the bots copy from the
  simulator lives in one class both call, with a test feeding both the same cases. **Watch out for:** a two-weapon
  carry made the simulator rebuy one shotgun 79 times; its shoppers bought past a 2.5 s drink that silently refused; a
  crane rule fixed in the bots stayed in the simulator. **Seen:** Deadnight #410, 2026-11-02; Deadnight #912,
  2026-11-03; Deadnight #959, 2026-11-04; Deadnight #1331, 2026-11-06 (fix: the drink finished in the break, one
  crane-odds class).
