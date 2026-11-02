---
areas: [net, tools]
---
# Two network stacks were hard to compare: no shared hook for bytes, latency or loss

2026-11-01

- **Saw:** the own protocol counts its own payload; the MultiplayerAPI and netfox expose no byte counter, and
  an in-game "conditioner" only wraps the stack that was written with one.
- **Cause:** every stack measured itself differently, so numbers could not be put side by side.
- **Fix:** a small asyncio TCP proxy between clients and the headless server counts bytes (WebSocket framing included),
  delays each chunk, and models TCP loss as a retransmission timeout that stalls every later chunk in that
  direction (head-of-line blocking). Server CPU comes from `psutil` over the same window. Works for any stack
  that speaks TCP, WebSocket included.
- **Docs:** Deadnight `spikes/net-compare/tools/run_scenario.py`; belongs on a kit page `docs/godot/multiplayer.md`.
