---
areas: [process]
---
# A green pull request with a recommendation waited for a yes

2026-11-06

- **Saw:** Deadnight #1199 and #1244 sat green and #1252 was refreshed with CI running, each parked with "merge?
  Recommended" in the handoff and in the report. The maintainer asked why merges waited for their approval.
- **Cause:** a recommendation was treated as a question. Merging is not on the list of maintainer decisions in
  `AGENTS.md`; the coordinator had already decided what it would do and passed the wait to the maintainer anyway, and
  each handoff carried the parked state forward without asking why it was parked.
- **Fix:** a pull request that the coordinator would merge is merged. Refresh it from main, let CI pass, land it, and
  report the trade-off afterwards so the maintainer can reverse it. Ask only for the listed maintainer decisions, for
  `S-hold`, or when there is no recommendation to give.
- **Docs:** [What the maintainer caught](../research/maintainer-corrections.md).
