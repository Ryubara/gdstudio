---
areas: [godot-ui, tests]
---
# A failed join showed nothing but a loading screen that never ended

2026-11-06

- **Saw:** the maintainer started a match from a lobby in the Discord Activity and it stuck on "Dusk at the drive-in" with
  an empty bar. The backend had answered and the game server had refused a socket that said no hello (Deadnight #1366).
- **Cause:** two faults made a failed join look like a hang. `NightScreen` adds `LoadingOverlay` after its card, so the
  overlay draws over the card that says "Could not join", and only a night that starts takes it away: a join that failed
  left it there for ever, with the reason and the Leave button behind it. And `Night.start_remote` said nothing to the
  bar until the night warmed up, so a join in progress and a dead one looked the same. Every test of a failed join ran
  headless, where the warm-up and so the overlay are off, and read the signal, never the screen.
- **Fix:** a failed join takes the loading screen away, and the online path says "Building the lot" and "Joining the
  night". `tests/ui/test_join_behind_the_loading_screen.gd` turns the warm-up on and reads what stands on the screen.
- **Check next time:** whatever covers the screen while something waits needs an exit for every way the wait can end, not
  only the good one. List them, and test each with the cover on: a headless run that switches the cover off proves
  nothing about what the player sees. A browser probe of the path to the game server does not reach Discord's proxy, so
  a join is not proved in the Activity by a native or a web join.
- **Not found here:** why the socket said no hello: that is #1366.
