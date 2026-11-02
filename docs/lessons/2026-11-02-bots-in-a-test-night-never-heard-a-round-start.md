---
areas: [tests, gameplay]
---
# The bots of a test night never heard `round_started`, so a stance based on it never engaged

2026-11-02

- **Saw:** a bot whose behaviour depends on the special round (hold a choke in the stampede) acted as in any round in a
  test, though `special_id` was right in the rules.
- **Cause:** the test began the round with `server.rules.apply(RulesAction.skip_break())`. The events of a direct
  `apply` are put in the server's outbox, which the next `step` empties before it starts, so no client, and no bot,
  ever hears them. (A bot seated after the round began misses the announcement the same way: the frame does not carry the
  special round.)
- **Fix:** `SeatedNight.start_round()` hands the rules' answer to the bot host (`host.hear(...)`); a stance that must
  survive a late seat should read the round from the frame once the server carries it.
- **Docs:** [bots research page, phase 3](https://github.com/Ryubara/deadnight/blob/main/docs/research/bots.md).
