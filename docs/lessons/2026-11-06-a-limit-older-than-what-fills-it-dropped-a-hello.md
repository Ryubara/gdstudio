---
areas: [backend, tests]
---
# A ticket grew past the hello's limit, and the server dropped it without a word

2026-11-06

- **Saw:** a match started from a lobby stuck on the loading screen in the Discord Activity, on every try, for one
  player. The game server logged `refused reason="SILENT"` (Deadnight #1366). Two probes and another Discord player
  joined the same server, so it read as Discord's proxy, then as a frozen main thread. Neither was it.
- **Cause:** the backend signs a player's finished challenges into the ticket once they wear a calling card, an emblem
  or a frame (#1158); the hello that carries the ticket had a limit of 1024 bytes from three days before (#422). Past
  it, the packet check struck the hello and said nothing, so the socket waited out its 10 s and was logged as a client
  that never spoke. Past 4 KB the engine's socket buffer closed it. Every probe was a fresh guest, whose hello is 500 to
  620 bytes: none could fail, and the player with the most progress was the only one who did.
- **Fix:** the limit and the buffer hold the longest ticket the backend signs (23.4 KB); a backend test reads the limit
  out of the game's source, so the two cannot drift; a hello past the limit is refused out loud.
- **How it was found:** the backend's log showed which client failed and which joined in the same lobby, so the fault
  followed the account and not the path. Then one run on production with throwaway guests and growing lists: 932 bytes
  welcomed, 1116 bytes silent.
- **Check next time:** when a report comes from one person, ask what that account holds that a fresh test account does
  not, and probe with a full one. A limit on a message and the code that fills it need a test that joins them across
  the two sides. A check that drops a message must say so: a server that answers nothing makes every cause look like
  the network. And `gh run rerun` replays the event it first ran on, so a pull request's old description comes back
  with it: edit the description to get a new run.
