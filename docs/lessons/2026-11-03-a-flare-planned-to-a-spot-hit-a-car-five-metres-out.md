---
areas: [gameplay, tests]
---
# A flare the bot planned to a spot hit a car five metres out

2026-11-03

- **Saw:** Deadnight #646: the bot ordered a flare for a spot 15 m away, the server burst it on "world" at 1.25 m height,
  4.7 m from the bot, and the lure landed on the bot instead of far from the body. A planner that asked "does a shot to
  this spot land within 3 m of it" then found a shot in one try in ten in the real lot, because the drive-in's cars
  (1.0 to 1.4 m tall) shut most lanes.
- **Cause:** a flare is direct fire at what the view meets (`AimResolver.aim_direction`), falling 4 m/s^2, and it bursts
  on the first wall or zombie. The first plan flew the shot once with the view exactly on the order; the motor fires
  within a degree, which moved the line a hand's breadth onto a car's corner. And one degree of pitch moves a low
  flare's landing 2.5 m at 15 m and 5.5 m at 22 m. The plan also asked for the wrong thing: where it was aimed, not
  where it lands.
- **Fix:** plan with the server's own `ProjectileState` and `AimResolver` in the bot's own world (the walls it can see and
  the dead it believes in), judge the rules at where the flare really lands (a car roof is a fine landing), and fly the
  shot again with the view turned a degree or two each way. A heading where the flare came up short shuts its neighbours
  for that plan; a plan that finds nothing waits a second. Wanted flares with a shot went from about one in ten to three
  in five.
- **Check for next time:** a bot that fires something that flies must plan with the same simulation the server runs, in
  the same world, with the aim error of its own hands, and must judge where it lands. A table made on flat ground only
  proposes lines.
- **Docs:** the game's `docs/research/flare-lure.md#bots-fire-it-646`.
