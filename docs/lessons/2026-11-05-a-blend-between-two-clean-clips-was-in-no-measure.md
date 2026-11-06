---
areas: [blender, tests]
---
# A blend between two clean clips was in no measure and put a hand 8 cm into the body

2026-11-05

- **Saw:** Deadnight's crawl blend-in put the right hand 81 mm (her) and 87 mm (him) into the trunk for about eight
  ticks (#1282, left over by #1037). `Downed_Idle` and `Downed_Crawl` each passed the clip sampler, and the tour only
  reached the blend because its crawl beat moves a downed player.
- **Cause:** the animation tree blends two full-body clips bone by bone, and the arm's straight way from the forearm
  over the knee (the sit) to the elbow on the ground (the crawl) crosses the belly and the thigh: 31-65 mm at weights
  0.1 to 0.5 whatever the phase of the crawl. Easing faster only shortens the time in it.
- **Fix:** a still waypoint pose for the arm (hand out and up beside the hip) that the arm passes through first, in a
  filtered Blend2: sit to waypoint, then that result to the crawl. Mixing the waypoint into a finished sit-to-crawl
  blend still left a band at weights 0.03-0.08 (31-38 mm), because the crawl's own pull is in the arm while the
  waypoint's share is small.
- **Check next time:** a blend is a pose the sampler never sees. For every pair of clips a tree blends between, evaluate
  the two clips' tracks at 0.025 to 0.05 steps of the weight over several phases of the looping one, and measure the
  skeleton's pose (`ClipFit.measure`), on both looks (the thicker jacket faulted a waypoint that was clean on her).
  Choose the waypoint by the path to it alone first; it is cheap (a still and one probe).
- **Docs:** Deadnight `docs/research/weapon-hold-ik.md`, "The poses #987 left over the tolerance (#1282)".
