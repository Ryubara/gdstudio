---
areas: [backend, net, tests]
---
# A bench's start command was left on the live game server and the next deploy ran the bench

2026-11-03

- **Saw:** to measure rooms of eight on Railway the bench was made the start command of `deadnight-server` (the one
  service the players use) for one deployment. Someone else's `deploy.sh` for a later commit then built a new
  deployment of the service, which took the bench command from the service settings: the live game server ran the
  bench for about fifteen minutes and listened on no port (Deadnight #712).
- **Cause:** a start command set with `serviceInstanceUpdate` is a setting of the service, not of the deployment. Every
  later deployment of the service reads it, whoever starts it. `railway redeploy` does the opposite: it reuses the old
  deployment's manifest and ignores a new start command, so the change looked like it needed a fresh `railway up`,
  which is exactly the step another agent also runs. Setting the field back to `null` through the API answers `true`
  and changes nothing; the value must be written (here the Dockerfile's own `CMD`, as a plain command: Railway runs a
  start command without a shell, so `exec ...` fails with "The executable `exec` could not be found").
- **Fix:** write the Dockerfile's command back (`godot --headless --path /app -- --server`), deploy with `deploy.sh`,
  and read the log for `event="listening"` and `capacity=3`.
- **Check for next time:** a measurement that needs a different command runs in a service of its own in the test
  project (`deadnight-rooms-bench`, deleted after), as the four-player measurement did, never as a change of the
  service that serves players. If a shared service must be changed, say so on the issue first, change it back in the
  same command that ends the measurement, and read the service's settings and its first log lines afterwards.
- **Docs:** Deadnight `docs/research/crowd-budget.md`, "Rooms of eight on Railway".
