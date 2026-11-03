---
areas: [tests, gameplay]
---
# A test put a zombie under a lob and expected the grenade to be stopped by it

2026-11-03

- **Saw:** two new GdUnit cases for "a zombie in the way of the arc stops the throw" failed on the first run: `plan` still
  returned a throw with a zombie standing 3 m out in the line (Deadnight #872).
- **Cause:** the bots throw high lobs (the heavy grenade hardly rolls, so a short throw is steep); at 3 m the arc is
  above 1.45 m, the top of a zombie's capsule (`ZombieBump`), so the grenade flies over it, as the real one does. The
  test assumed the zombie met the arc where the zombie was, not where the arc was.
- **Fix:** the test builds a low throw whose arc is a metre up at the chosen distance (scanning the pitch with the
  same formula `arc_is_open` uses) and puts the zombie there: in line it stops the throw, a metre to the side it does
  not, at 9 m (past the safe distance) it does not.
- **Check:** a test of a thrown arc against a body works out the arc's height at the body's distance first; "in the
  line" is not "in the way".
- **Docs:** Deadnight `game/tests/bots/test_bot_grenadier.gd` (`_throw_low_at`).
