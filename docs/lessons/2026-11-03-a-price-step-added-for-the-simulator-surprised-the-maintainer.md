---
areas: [gameplay, process]
---
# A price step added to tame the simulator became a rule the maintainer never asked for

2026-11-03

- **Saw:** playing round 12, the maintainer found the re-cut bench asking 3,000 for his second weapon and said it should
  cost 5,000 every time, once a weapon (Deadnight #909). The genre's station he had in mind was a flat 5,000.
- **Cause:** the design had set the bench to 1,500 plus 1,500 for each weapon already re-cut (`UpgradeTuning.price_step`,
  and `recuts_lost` so that giving a weapon up did not reset it), because the first simulator runs let a strong solo
  player re-cut four weapons a night. That is the model's behaviour, and the model already has its own stopping rule
  (`SimSkill.re_cuts`); the step was a second lever on a player-facing price, and the research page that listed the
  genre's flat 5,000 set it aside as "barely matters". A price a person pays is a rule they read off the card.
- **Fix:** the price is the item's alone (5,000), the step and `recuts_lost` are gone (rules snapshot 15), the
  once-a-weapon refusal says why on the card. The gate moved from 5 / 13 / 15 / 16 / 18 / 18 to 5 / 11 / 14 / 16 / 17 /
  17 and stayed inside its bands, with no retune. Check: fix what the simulator's player does in the player's policy (how
  many, in what order), never in a price or count a person sees; when a design departs from a reference value the
  maintainer knows (a genre price, a once-a-weapon rule), name the departure as a question in the issue.
- **Docs:** Deadnight `docs/research/weapon-upgrade.md`, "5,000 flat, once a weapon (#909)".
