---
areas: [gameplay, tests]
---
# A bot flipped between two errands and did neither

2026-11-03

- **Saw:** a bot at a shop machine in an area whose circuit was off alternated `breaker <circuit>` and `buy <item>` at
  every sample and never bought (Deadnight #706, found in the ticket plaza).
- **Cause:** the want for the first errand depended on where the bot stood ("a person is in the area"), and the
  errand's own walk (to a breaker outside the lamps' reach) ended that condition. The want dropped, the shopping
  errand took over and walked the bot back in, and the want returned. The map the test ran on had every breaker beside
  its machine, so no suite saw it.
- **Fix:** an errand whose want is a position of the bot is kept from the moment it begins (the breaker is wanted
  until it is on, for one errand limit); the test shrinks the lamps' reach on the shipped map so the breaker is
  outside the area, and fails on the old code with the notes flipping.
- **Check:** for each errand, ask whether walking it changes the thing that made it wanted; if so it needs a
  commitment (a kept id and a deadline), and its test puts the goal where the walk leaves the condition.
- **Docs:** Deadnight `BotErrands._breaker_id` (`game/gameplay/bots/bot_errands.gd`).
