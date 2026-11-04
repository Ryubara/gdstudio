# Deadnight's performance review (#907)

The first review made with the [Performance review](../godot/performance-review.md) checklist: Deadnight `origin/main`
0fe9a1ff (2026-11-03), after the maintainer asked (Deadnight #906 and #907) for the places that "will definitely lag the
game". The reviewer opened nine issues; all but #935 are closed. This page keeps the numbers and what the review could
not see, so the next review starts from them.

## Verdict

The crowd itself is well built: zombie views, blood, impacts, tracers, damage numbers and sounds are pooled and capped,
navigation is staggered and budgeted, the bots spend a ray budget, the shaders are few. Four nights in a row left 57
nodes each (the baseline), with resources within 5 % and memory within 2 % of the first. The cost was in what was done to
the crowd 60 times a second, and in an effect that was never freed.

## The tick, measured

A real `Night` with the HUD, 3 bots, 3x count, round 12, the autopilot, the desktop ceiling (120), headless at
`--fixed-fps 60`, an editor (debug) build, on a machine with 20 to 40 other Godot processes: read every millisecond as
1.5 to 2 times a quiet machine's, and the counts as exact. 3,840 ticks with 85 or more standing (about 98 alive).

| Label | Mean per tick | Share of 16.7 ms |
| --- | ---: | ---: |
| `tick.server` (all server work) | 5.8 ms | 35 % |
| `tick.pump` (client: events, views, voices, HUD) | 4.4 ms | 26 % |
| `tick.bots` and `tick.bot` | 1.7 ms | 10 % |
| Sum | 11.9 ms | 71 % |

At 40 alive (the web ceiling) the same night cost 3.9 ms: 2.45 times the dead cost 3.0 times the time. The ceiling of
120 was set from the server step and the client draw (`crowd-budget`), without the client's GDScript per tick, which is
as large as the server's step. About 4.8 ms of the 11.9 was crowd work done at 60 Hz for data that changes at 30 Hz, or
decoded five times.

## Findings, by expected cost

| Issue | What | Cost and scaling |
| --- | --- | --- |
| #930 | The crowd decoded five times a tick (person, each bot, the horde) | 0.15 to 0.29 ms each at 100 alive; 3 to 4 ms of the tick, half redundant; grows with the bots |
| #931 | Server crowd lists built twice a tick | 0.77 ms at 98 alive; a host with bots builds the whole frame every tick (1.9 ms) |
| #929 | `BlastEffect` never freed | per blast 3 alpha-0 draw calls and a visible energy-0 light for ever; per blast-killed zombie 7 nodes; unbounded |
| #932 | `ZombieView.dress` when a blast cripples | 0.42 ms median, 2.4 ms worst per zombie; 20 crippled is 8 to 12 ms in one tick |
| #933 | Separation allocates | 0.63 to 1.2 ms per 30 Hz step for 120 dead |
| #938 | Bot camera rigs stepped every frame | 43 us a rig a frame; scales with bots and refresh rate |
| #936 | Grenade trail dots | a 4,224-triangle sphere, material, node and tween per dot, 30 a second |
| #934 | Marquee redraws every frame | about 100 `draw_circle` polygons a frame in a special round; heap churn on the web |
| #935 | Web probes read the page every frame | about 4 JavaScript reads and an Array a frame, for tests that run under `?probe` |

## Minor, seen and left

- `NightLight._process` writes the ambient, sky, fog and moon every frame though the level eases for seconds a round.
- `LightFollower._process` (11 subclasses, 8 running in a night) re-reads its lamp and re-sets shader parameters.
- `NightMarkers._process` builds a fresh list of dictionaries a frame; the markers layer redraws every frame with allies.
- `ShotEffects.blood_hit` asks `ResourceLoader.exists` with a built path on every hit (about 3 us).
- A bought door costs +11 to +15 ms in the frame of the purchase, and 35 to 40 ms in one of the next six frames. Five
  doors a night; accepted.

## Not verified (needs a windowed run on a quiet machine)

1. Lights in view. The lot has 55 omni and 8 spot lights (42 and 6 visible in the tree), and `project.godot` sets no
   `rendering/limits/opengl/*`. The test covers the per-mesh cap of 8 only; the per-frame renderable cap was believed to
   be 32 and is not checked against the 4.7 docs. Count the visible lights in the camera poses of the room tour, with a
   fight on top.
2. Draw calls and fill with 100 alive, four soldiers and the HUD (the crowd bench has no HUD and read 149 draw calls at
   120).
3. Blood and outline fill at point blank (the blood splash shader loops 16 times a pixel over a quad up to 2.4 m wide).
4. The editor against an exported build, the same night in both.
5. A 30-minute soak (#906). The 7-minute run (4,253 nodes rising to a plateau of 5,500 to 5,750 from second 40, orphans
   0) showed no unbounded growth.

## Method notes

- Counts are exact on a loaded machine; times are ratios between arms run together
  ([measuring without a quiet machine](../godot/performance-review.md#how-to-measure-it-counts-first)).
- Stop a run by its own process id: the reviewer's `taskkill /IM` of the Godot console ended every agent's run
  ([lesson](../lessons/2026-11-01-killing-godot-by-name-stopped-other-agents-runs.md)).
