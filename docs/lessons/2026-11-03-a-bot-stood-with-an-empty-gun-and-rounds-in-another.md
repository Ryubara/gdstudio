---
areas: [gameplay, tests]
---
# A bot stood with an empty gun while another gun held its rounds in reserve

2026-11-03

- **Saw:** the nightly bot soak (Deadnight #231) flagged bots standing in a fight, over ten seconds, with a zombie in
  view; every sample read `ammo 0/0` in hand. In one boss fight a bot held an empty shotgun for two minutes with 24 rifle
  rounds in reserve (`rifle [0, 24]`). Four Regular bots reached round 9 against the simulator's 15.
- **Cause:** `BotArsenal.plan` swapped away from a dry gun only to a weapon with a *loaded magazine* or a crowbar. A gun
  with its magazine empty and rounds in reserve was not a candidate, and the quick melee is no carried weapon, so the
  plan did nothing. Unit tests had every dry case with a loaded second gun, a crowbar or a reserve in hand.
- **Fix:** swap to a gun that has reserve rounds when nothing else can fire (it is reloaded once in hand), with a test of
  the three cases (Deadnight #744 landed the same change while the soak was being built). With it kills a bot-minute
  went from 3.7 to 6.0 and the median round of four Regular bots from 9 to 12 (12 nights each).
- **Check next time:** a soak that prints what each bot held when it stood idle (`idle_samples` of `bots_soak`) finds
  this kind of hole in minutes; read those samples before tuning anything by the median round.
- **Docs:** Deadnight's `docs/research/bots.md#phase-7-validation-at-scale-and-tuning`.
