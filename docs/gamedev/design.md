# Designing from a reference

<!-- new section: gamedev/ held only level design and audio; nothing covered planning a game against the reference it
learns from (its loop, numbers, variety, settings, bot teammates and content), which every new game starts with -->

What a game takes from the reference it is studied against, and what it plans from the first day so the maintainer
does not have to add it later. The reference is studied for its design and its numbers; its content, names and assets
are never copied. The checklist for a new game is
[Start of a new game](../studio/plan-from-the-start.md#start-of-a-new-game); the HUD is on
[UI and HUD](ui.md#hud), the camera, devices and feel on [The player's controller](controller.md).

## The reference's loop and numbers {#reference}

Name the loop the reference game is built on and the numbers that tune it (movement, enemy tiers by round, damage,
economy), cite where each comes from, and only then tune.

- **Approach:** Name the reference game's core loop and how it is tuned, and plan a balance simulator with its CI gate
  alongside the first systems: balance and a real wave system are part of the concept, not extras. **Watch out for:**
  the reference genre was read as a list of features rather than a tuned loop. **Seen:** Deadnight, 2026-11-01 (fix: the
  checklist for a new game plans the simulator on the real weapons and tuning, with its gate ([Start of a new
  game](../studio/plan-from-the-start.md#movement-and-numbers-against-the-reference))).
- **Approach:** Collect the reference's movement numbers (enemy tiers per round, the player's walk, sprint and aim) and
  cite them before tuning any speed. **Watch out for:** Deadnight's zombie speeds were set without the reference's
  ratios to the player's walk and sprint. **Seen:** Deadnight, 2026-11-01 (fix: zombie speed was researched against the
  reference's walk and sprint, and a new game collects these numbers first).

## Variety beats {#variety}

The base loop holds for a few rounds; what keeps it going is variety, each beat signalled so the player knows it came.

- **Approach:** List the reference's variety beats (boss rounds, special rounds, enemy types) and how each one is
  announced to the player, and plan them with the loop. **Watch out for:** the base loop was copied without the variety
  that keeps it interesting. **Seen:** Deadnight, 2026-11-01 (fix: boss rounds and zombie types, each clearly announced,
  went into Deadnight's plan).

## Settings that scale the game {#settings}

A setting the players choose (more of the dead, faster rounds) changes how the game feels, not how long it lasts.

- **Approach:** Make a multiplier on a game setting scale the intensity the player feels (a 3x count is a 3x spawn rate
  too), not the length of a round, and add no limit or fail rule the maintainer did not ask for. **Watch out for:** a
  count multiplier was read as more zombies over a longer round, and a time limit with an overtime rule was added
  unasked. **Seen:** Deadnight, 2026-11-01 (fix: rounds have no time limit, and a test checks that a round lasts about
  as long at 1x, 2x and 3x ([lesson](../lessons/2026-11-02-a-scaling-setting-needs-a-pace-test.md))).

## Bot teammates {#bot-teammates}

A bot that fills a player's seat is a teammate: it has to do everything a player does.

- **Approach:** Decide early whether the game needs bot teammates; if it does, research them in depth (reviving, buying,
  moving, every weapon) before building the systems they use. **Watch out for:** Deadnight's bot was a test tool, not a
  teammate. **Seen:** Deadnight, 2026-11-01 (fix: the teammate bots were researched before they were built on those
  systems).
- **Approach:** Before setting a gate on how an AI teammate behaves, ask what it does by default and what the player can
  order; build the orders (Follow, Roam, Hold) as a player control and gate each order on its own. **Watch out for:**
  the bot research made every bot a follower gated on staying within 12 m of a person 95% of the time, and agents tuned
  toward that gate for a day, where bots that roam and act, come for a revive or a ping and take orders from a wheel
  were wanted. **Seen:** Deadnight #564, 2026-11-03 (fix: deadnight #641 and #642 built the orders).
- **Approach:** When a teammate bot gets a reply to a player input, list its own needs first and write the
  needs-against-orders table in the same pull request; distances a bot acts on are walk lengths. **Watch out for:**
  resupply was added as one more reply to a person's ping (Deadnight #647, #670), so the bot's own want of ammo had
  nothing to rank against once orders landed, and the nearest locker was measured in a straight line. **Seen:**
  Deadnight #692, 2026-11-03 (fix: the ask for bots that fetch their own ammo showed it
  ([lesson](../lessons/2026-11-03-a-teammate-bot-had-answers-to-a-person-and-no-needs-of-its-own.md))).
- **Approach:** When a bot spends and then uses what it bought, price the spend by the chance the use says yes, count
  paid, offered and used per bot in a real night, have a test named for an outcome assert it (the weapon in the arms),
  and walk a waiting bot back. **Watch out for:** a bot paid when any of seventeen prizes would do but took only one
  that beat its hands 1.5 times, so 32 of 34 prizes stayed on the glass and it paid again; a shove left it waiting away,
  and the errand test asserted only that a play was bought. **Seen:** Deadnight #1322, 2026-11-06 (fix: seen in play;
  the counts per bot are the check).

## Content beyond the starter kit {#content}

A starter kit gets a game to its first playable; what the design needs beyond it is planned as art work.

- **Approach:** Inventory the starter kit against everything the design needs and plan each gap as an art task. **Watch
  out for:** the starter kit was assumed to be enough content, and it had few guns for a shooter. **Seen:** Deadnight,
  2026-11-01 (fix: the missing weapons were planned as art tasks in the game's style).
- **Approach:** Put materials and the kit's own props on the map as soon as its layout holds. **Watch out for:** the
  greybox stayed while the systems grew, and the map looked unfinished long after it played. **Seen:** Deadnight,
  2026-11-01 (fix: textures and kit props went onto Deadnight's map).

## An animation for every interaction {#interactions}

An interaction is not finished when its state changes; it is finished when the player sees it happen.

- **Approach:** Ship every interaction (repair, buy, revive, tear) with its animation, the actor's clip and the object's
  motion, in the same feature, or file an issue for it. **Watch out for:** interactions shipped as a change of state
  with a stand-in effect; tearing and repairing boards had no real animation. **Seen:** Deadnight, 2026-11-01 (fix:
  board tearing and repair got their animation).
