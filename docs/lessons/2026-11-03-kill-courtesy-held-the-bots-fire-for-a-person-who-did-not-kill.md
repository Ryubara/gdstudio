---
areas: [gameplay, tests]
---
# Kill courtesy held the bots' fire for a person who never fired

2026-11-03

- **Saw:** the soak's Follow nights: a bot with a loaded gun, `note hold`, no target and a zombie in sight 6 to 12 m away,
  for 6 to 12 s (Deadnight #770). Every sample had `target_id -1`: nothing was chosen to shoot.
- **Cause:** a rule that yields to a person ("a zombie a person is aiming at is theirs, 7 degrees, 25 m, 6 m or more
  from the bot") had no end: the person stand-in kept its aim on a zombie with a dry pistol, so the zombie stayed theirs
  for as long as the aim did. A human who watches a zombie they cannot kill does the same.
- **Fix:** every rule that makes a bot wait for a person needs a time limit and a test that runs past it: a zombie left
  to a person is the bot's after `BotCombat.COURTESY_SECONDS` (3 s), counted per zombie, and
  a person who looks away for a
  moment does not give it back.
- **Docs:** Deadnight `docs/research/bots.md`, "Idle bots and stalled rounds with a person (#770)".
