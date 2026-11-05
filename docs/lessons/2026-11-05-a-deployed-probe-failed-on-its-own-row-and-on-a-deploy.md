---
areas: [net, backend, tests]
---
# A deployed probe failed on the row it had just left and on a deploy of the backend it was reading

2026-11-05

- **Saw:** Deadnight's `deployed_leaving_probe.tscn --ended` failed 2 of 16 on production (#1240): `tab then list`
  (`join-by-code` answered `not_found` for the first row of the list) and `ended` (the reopened lobby never read `open`
  within 40 s). It had passed 16 of 16 four times that morning. A rerun failed the first one again at once, and passed
  the second.
- **Cause:** two different things. (1) The probe joined the first row of the list; that was the night it had just left
  (the socket closed, and the game server's `/left` takes it out of the list a moment later), so the join raced its own
  removal on every run. The branch had come with the Server Browser, after the passing runs, and had never run on
  production. (2) Lobbies live in the memory of one backend and production deploys it every few minutes as main merges;
  the backend's logs (`railway logs -d <deployment id> --service backend`) showed the lobby made on the old container,
  the new one listening mid-night, and 36 s of `404` on `preview`. Nobody could have passed that check; the product was
  working as documented.
- **Fix:** the probe joins the row it set up itself (a friend's waiting room that a stand-in reads every two seconds so
  it is listed), never "the first row", and checks that the night it left is out of the list. `GET /health` names the run
  of the backend (`boot`), and a failing run whose `boot` changed ends `INCONCLUSIVE` (exit code 2) instead of failing.
- **Check for next time:** a probe against a shared, continuously deployed environment (1) acts only on things it made,
  never "the first thing listed", and (2) says which build it ran against and whether that changed during the run: read
  the deployment list (`railway deployment list --service <name> --json`) and the logs of the deployment that was live
  in the failing minutes before calling a failure a fault, and check a failing run's time against them.
- **Docs:** the game's `docs/design/lobby.md` ("The deployed probe, and two ways it failed on production").
