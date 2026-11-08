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
  **Seen:** Deadnight #897, 2026-11-03; Deadnight #898, 2026-11-03 (fix: deadnight `test_starter_pistol.gd` ([melee
  lesson](../lessons/2026-11-03-a-melee-blow-one-tapped-because-its-sweep-always-met-the-head.md), [start weapon
  lesson](../lessons/2026-11-03-a-start-weapon-one-tapped-the-first-two-rounds.md))).

## A weapon is a model, a definition and a source {#roster}

A model is a weapon only when it has a definition (its numbers) and a source a player can reach (the start, a wall, a
drop). Art, definitions, the shop and the drops are one list.

- **Approach:** Keep art, definitions, the shop and the drops as one roster table (model, definition, source, numbers),
  with a test that every definition has a source a player can reach and every source names a real id; an unclear model
  is a question to the maintainer. **Watch out for:** there were 10 weapon models and 6 definitions; the bat and the
  fire axe had models and holds but no id, numbers or source, and the prize crane's pool was a hand-written list of
  four. **Seen:** Deadnight #461, 2026-11-02 (fix: every weapon got a definition and a source, Deadnight #530).

## Comparing weapons {#comparing}

"Weaker" and "stronger" are judged on more than one axis: damage per hit, ammunition and reload upkeep, range, reach.

- **Approach:** When a rule says "weaker" or "stronger", name every axis it is judged on (damage per hit, ammunition and
  reload upkeep, range, reach), and class a weapon of another kind by its kind (`WeaponDef.is_melee`), not by a row
  someone can add. **Watch out for:** the wall-tier rule ranked weapons on damage per hit alone, so the crowbar, bat and
  axe, which never run dry, landed in the lowest tier a wall may sell. **Seen:** Deadnight #910, 2026-11-03 (fix: a wall
  sells only weapons that cost upkeep
  ([lesson](../lessons/2026-11-03-a-tier-rule-on-one-axis-let-melee-onto-the-walls.md))).

## Prices the player reads {#prices}

A price or a count on a card is a rule the player reads and remembers. What the balance simulator's player does is set
in its policy, never by changing what a real player pays.

- **Approach:** Tame the balance simulator in the simulated player's policy, never in a price or a count the player
  reads; when a design departs from a reference value the maintainer knows (a genre price, a once-a-weapon rule), name
  the departure as a question in the issue. **Watch out for:** the re-cut bench cost 1,500 plus 1,500 per weapon already
  re-cut only because early simulator runs let a strong solo player re-cut four weapons a night, though the model had
  its own stopping rule. **Seen:** Deadnight #909, 2026-11-03 (fix: a re-cut costs 5,000, once a weapon
  ([lesson](../lessons/2026-11-03-a-price-step-added-for-the-simulator-surprised-the-maintainer.md))).

## A score's smallest step {#denomination}

A score is a currency with a denomination: its smallest step is decided once, and everything is rounded to it in one
place.

- **Approach:** Fix a score's smallest step in the first design and round every award, price and loss to it in one place
  on the server after the last multiplier, with a test of seeded full nights that fails on anything off the step;
  rounding a tuning number is a retune, so the balance gate runs in the same pull request. **Watch out for:** points had
  no unit: tunings stepped by 1, a zombie type's multiplier rounded to whole points, each purchase rounded its own way,
  and the HUD showed sums like 31 to 34. **Seen:** Deadnight #916, 2026-11-03 (fix: `PointSteps` (award nearest, price
  up, loss down) in steps of 5
  ([lesson](../lessons/2026-11-03-points-came-in-any-amount-until-one-rule-rounded-them-to-fives.md))).

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
