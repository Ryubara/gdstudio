---
areas: [gameplay, process]
---
# A 3x zombie count made rounds longer, and a time limit was added to patch it

2026-11-02

- **Saw:** the match settings' 3x count only multiplied the count, so rounds lasted longer; a round time limit was
  added to cover it. The maintainer pointed out that rounds should have no time limit at all, and that a 3x count
  means a 3x spawn rate as well (Deadnight #449).
- **Cause:** one scaled quantity, with the spawn interval and the alive cap left as they were. Even with the rate
  scaled, the alive cap held 3x back (rounds 15 to 26 percent longer). The unscaled interval went into the docs as an
  open question instead of being treated as the bug.
- **Fix:** count, spawn rate and alive cap scale together; no time limit; a test that each round at 2x and 3x lasts
  within about 10 percent of 1x.
- **Check:** when a setting scales a quantity, ask what it does to round length and pace, and measure it; never add a
  new mechanism (a limit, an overtime) to cover a side effect of the first.
- **Docs:** [What the maintainer caught](../studio/maintainer-corrections.md).
