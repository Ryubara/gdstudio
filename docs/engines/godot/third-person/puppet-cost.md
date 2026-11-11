# What an online puppet costs

<!-- new section: online-client.md reached its size limit; nothing else held what a puppet costs a browser frame -->

How much of a browser frame another player's body (a puppet, [puppets](online-client.md#puppets)) takes in 3D Third
Person, where it went and what took it down. Part of [the online client](online-client.md); the probe is
[playing online](online-client.md#play-online).

## A puppet's frame {#puppet-cost}

<!-- new section: online-client.md reached its size limit; the split of a puppet's frame cost (gdstudio #1138) and the
     bench that measures it had no room there -->

The online scene hands every puppet to its `PuppetAnimationThrottle` (`RemotePlayers.animation_throttle`, a
`CharacterAnimationThrottle`, the AI's [animation throttle](ai.md#animation-throttle) without the tiers): within 15 m
of the camera a puppet animates every frame and plays its footsteps, out of view past that it holds its pose, and past
25 m it moves every sixth frame. Like every character, its meshes are on `CharacterModel.body_layers` (layer 2), which
the minimap's live camera does not draw. What the two save is below.

Seven puppets on one GPU page, uncapped, the frame
with one part of the puppets taken out at a time (one run each, so a millisecond either way is noise): all in, 8.6 ms;
no puppet, 2.3; the trees frozen, 4.1; the models hidden, 4.3; the weapon hold's modifiers stopped, 7.6; the footsteps
off, 9.2; the puppets' meshes off the minimap's layer, 5.4. `tools/bench/puppet_bench.tscn` (`puppet_bench.py`) puts
the same seven puppets walking in front of a camera with no level and no minimap: each costs 0.2 to 0.25 ms on the GPU
(0.06 the animation's CPU work, the rest skinning and drawing; frozen, 0.02) and 1.3 ms on SwiftShader (0.56 frozen).
So three quarters of a puppet's millisecond in the game was the minimap: its live camera (`map_update_rate` 0, every
frame) drew every layer-1 mesh, so every puppet, on screen or not, was skinned and drawn a second time each frame.
Every character's meshes are now on layer 2 (`CharacterModel.body_layers`), which the minimap leaves out (its marker
shows the body), and the puppets have an animation throttle ([puppets](online-client.md#puppets)) for the ones out
of view or far.
The same probe after both (two runs each; the rows before are the table above):

| Puppets | Renderer | Frame p50 / p95 before | Frame p50 / p95 after | Puppets animated a frame |
| ---: | --- | ---: | ---: | ---: |
| 0 | GPU, uncapped | 1.7 to 2.2 ms | 2.3 to 2.4 / 3.2 to 3.3 ms | 0 |
| 1 | GPU, uncapped | 4.1 to 6.6 / 5.5 to 10.0 ms | 4.0 to 4.1 / 5.3 to 5.6 ms | 1 |
| 4 | GPU, uncapped | 7.6 to 7.8 / 10.3 to 11.0 ms | 4.4 to 5.6 / 6.0 to 9.4 ms | 1.1 to 1.4 |
| 7 | GPU, uncapped | 10.5 to 14.3 / 13.6 to 18.3 ms | 3.8 to 4.2 / 5.6 ms | 1.3 to 3.0 |
| 0 | SwiftShader | | 27.5 to 28.2 / 30.9 to 31.2 ms | 0 |
| 1 | SwiftShader | 42.8 / 48.7 ms | 41.6 to 42.3 / 45.6 to 45.8 ms | 0.5 |
| 4 | SwiftShader | 46.1 / 50.6 ms | 42.7 to 44.2 / 48.4 to 49.6 ms | 0.9 |
| 7 | SwiftShader | 51.8 / 63.7 ms | 45.5 to 48.5 / 52.8 to 60.8 ms | 1.6 |

From one puppet to seven a puppet now adds about 0.0 to 0.03 ms on the GPU (1 to 1.3 before) and 0.6 ms on SwiftShader
(1.5 before). Interleaved on the same build (seven puppets, GPU), the layer alone read 5.0 and 6.6 ms against 8.6 and
9.9 with the puppets back on layer 1, and the throttle on top 4.0 and 5.0. The throttle's share depends on where the
puppets are: within 15 m of the camera a puppet animates every frame, so seven puppets in a close fight cost what the
bench's `near/full` does (0.2 ms each on the GPU, 1.3 on SwiftShader); out of view or past 25 m they cost almost
nothing. `OnlineProbe` reports `puppets_animated`, the puppets whose tree moved on in a frame.

- **Approach:** Split a per-character frame cost two ways before changing anything: take one part out at a time in
  the real scene, and bench the character alone; a gap between the two is something else in the scene. **Watch out
  for:** the issue and the first write-up put a puppet's millisecond on its animation and skinned model, but a bench
  of seven puppets without a level read 0.2 ms each: the rest was the minimap's live camera drawing every body again
  ([minimap cost](../minimap.md#cost)), and throttling the animation alone would have left most of it. **Seen:**
  gdstudio #1138, 2026-11-11 (`tools/bench/puppet_bench.tscn`).
