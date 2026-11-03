---
areas: [tests, gameplay]
---
# A test that seated bots by hand left out the table that tells a bot who its neighbours are

2026-11-03

- **Saw:** `test_a_remote_persons_order_reaches_the_bots_and_they_keep_it` (Deadnight #676, bot orders) passed 5 of 5
  locally and failed once on CI: "bot 3 is 3.1 m from the spot", against a bound of 3 m. A probe of both bots every half
  second showed one parked at 2.97 m, on a ledge 1 m up, for 25 s; the other at 1.13 m.
- **Cause:** the test made each bot as a client of the server, but not the shared `bot_ids` table (and team) that
  `BotHost` hands every bot. The frame does not say which seat is a bot, so each bot took the other for a person,
  saw itself alone, and the Hold order's ring (one place per bot about the spot) collapsed to one place: both pressed
  against the person's body and each other and were pushed off by whatever the timing was. 2.97 m was 3 cm under the
  bound, so a slower runner crossed it. The code was right; the test did not build the thing it claimed to test.
- **Fix:** the test shares one `bot_ids` table and one `BotTeam` between its bots, as the host does, counts the half
  seconds inside 3 m over five seconds (the rule is a share of the time, not an instant) and asserts the two bots stand
  more than 2 m apart, which fails without the table (checked by removing it). 5 of 5 pass.
- **Check for next time:** a test that makes a `BotClient` by hand copies every line of what `BotHost.seat` does
  (`bot_ids`, `team`, the legs), not only the ones it needs to compile; a distance bound that sits within a few
  centimetres of what a probe measures is a sign the setup is wrong, not that the bound is right. Log the thing for
  the whole run before choosing between "widen the bound" and "fix the cause".
- **Docs:** [Test speed](../godot/test-speed.md).
