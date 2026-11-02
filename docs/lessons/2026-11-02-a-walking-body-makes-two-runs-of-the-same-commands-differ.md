---
areas: [tests, gameplay, godot]
---
# Two runs of the same commands gave different nights once a body walked

2026-11-02

- **Saw:** the replay test of the bot host (Deadnight #225) recorded four bots' commands over 900 steps and played them
  into a fresh server of the same seed: the state hash matched in about half of the runs. Two live runs of the same
  bots gave two different command hashes as well. The first difference was 1e-5 m in one walking player's position
  (`-42.97185` against `-42.97184`) on the first step it moved; a fight then amplified it to a zombie a quarter metre
  away 300 steps later. With bots that stand still, or a night with no contact, every run was identical. A second
  source showed once the bots stood and fought: a zombie that walked round an obstacle by one of two tied routes ended
  0.75 m from its twin in the other world, in about a run in four, and a kill moved from one bot to the next.
- **Cause:** a `CharacterBody3D` moved by `move_and_slide` does not give the same result to the last bit in two world
  instances (and two processes): the order the physics engine meets contacts in follows ids and addresses, so float sums
  differ in the last digits; the navigation mesh breaks a tie between two equal routes by polygon ids, which differ
  between worlds. The rules, the bots and the zombie simulation's own arithmetic are deterministic; the engine's body
  and its route choice are not.
  Separately, the last bit of a float from `sin`, `cos` and `atan2` can differ between Windows and Linux, so a golden
  hash over raw floats cannot hold on both.
- **Fix:** a determinism test lets nothing walk (the bots stand and fight, `retreat_margin = 0`) and puts every zombie
  once on open ground in front of a bot, to walk in a straight line (no route to tie), compares a coarse state (the
  rules, positions in quarter metres, health, ammunition, kills) and checks that a fight happened. A golden hash
  of what the bots send is made of the buttons, the walking direction in eighths and the view in 5 degree buckets
  (`BotTelemetry.signature`), over a rig with no physics engine (`BotRig`). Do not assert bit equality of anything a
  physics body went through. Before trusting a replay test, run it a dozen times.
- **Docs:** Deadnight `docs/research/bots.md` (Determinism and testability, Built in phase 1).
