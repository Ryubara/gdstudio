---
areas: [gameplay, tests]
---
# A bot stood among the dead for the rest of the night and never shot: they were behind it

2026-11-03

- **Saw:** a forty-minute bot night on the second map (one bot, seed 7) never closed round 10: the bot stood at a
  "choke" with three dead attacking it at 0.3 to 0.6 m, shotgun and Tommy gun loaded, no target (`tgt=-1`), no shot.
  The trace showed `ctc=1 vis=1 tg=0`: a contact, visible, and no target (Deadnight #695).
- **Cause:** a contact is believed only after its reaction delay, and a contact still inside that delay is erased when
  its zombie is out of the view cone at a think. The bot faced away from the dead behind and beside it, so each one
  was erased and made again (age 0.0 to 0.1 s in the probe) at every think and never got past the delay.
- **Fix:** a zombie in its swing within 2 m is noticed whichever way the bot faces (`BotPerception.ARM_REACH`); the
  reaction runs once. A perception test puts a swinging zombie behind the bot (fails on the old code) with controls
  for a walking zombie at the same place and a swinging one at 6 m. Check: a stalled bot night is read from the bot's
  own beliefs (contacts, visible, targets, the contact's age) before a cause is guessed; a rule that drops a contact
  at one look is tested with a zombie that leaves the view while it is hitting the bot.
- **Docs:** Deadnight `docs/research/bots.md`, `BotPerception`.
