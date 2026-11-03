---
areas: [gameplay, tests]
---
# The bots hit themselves with their own grenade, and the throw was not where it went wrong

2026-11-03

- **Saw:** with the bots' 7.5 m teammate clearance taken away (Deadnight #856, then #872) they threw twice as often
  and 12 of 42 blasts touched the thrower, two over a tenth of its health; the soak failed on seeds 11 and 12.
- **Cause:** four things, none in the choice of the throw. The brain dropped the order when a person walked near the
  landing, but the motor only stops a throw while the view still turns, so the grenade flew and the bot walked on to
  follow. After the order the bot followed again and ran the last 10 m of the blast in the 2 s left (it stepped out only
  inside the blast's edge). Giving way to a person moved a still bot 3 m toward its blast, and a retreat rated headings
  by what flees the dead, so a blast that stood on the pack's side weighed as one zombie and the bot ran at it. And the
  grenade lay 3 to 6 m short of the aim (a wall or prop over a lob) while the bot kept out of the point it aimed at.
- **Fix:** a bot stands and fights while its own grenade is live (20 m), headings toward it are dropped from a retreat
  and from the legs' giving way (`keep_out`), and the bot hears `grenade_bounced` to move its blast to where the grenade
  lies. The probe that found it printed, per blast that touched its thrower, the bot's distance to the real blast every
  half second beside its note and the grenade's bounces: read it before guessing, and take "the planned landing" from the
  bot's own order, not from the newest entry of a list every bot writes to (the first reading showed another bot's plan).
- **Check:** measure a bot's self-damage over twelve nights, not six (the same seed gave 0 and 1 blasts over a tenth on
  unchanged code), with a separate checkout of `main` as the before; count the share summed over blasts as well as the
  worst, so one outlier does not hide a trend.
- **Also:** a hook run of `gdformat` wrote CRLF line endings into three GDScript files on Windows: `git diff --stat`
  warned "CRLF will be replaced by LF", and an edit script that asserted no `` stopped on it; `sed -i 's/$//'` fixed it.
- **Docs:** Deadnight `docs/research/grenades.md`, "The bots and their own grenade (#872)".
