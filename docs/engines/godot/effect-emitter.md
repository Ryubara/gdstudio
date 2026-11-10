# The effect emitter and the muzzle flash

<!-- new section: the 3D Third Person template's one-shot effects (gdstudio #888) and nothing else held how a
     pooled emitter is used or what it costs; the template page holds the short version -->

How the 3D Third Person template plays one-shot effects: the pistol's muzzle flash, each bullet impact and anything a
game adds go through one pooled `EffectEmitter`. Built and measured in Godot 4.7.2 (Windows, an RTX 5080, and the web
export in Chromium); the template's own part is on [the template page](third-person-template.md#effects), the rules
every one-shot effect follows on [Pooled and one-shot effects](one-shot-effects.md#the-rule), the flash's look on
[Shot feedback](shot-feedback.md#muzzle-flash).

## Using it {#using-it}

One `EffectEmitter` in the level (`Effects` in `world/world.tscn`, the group `effect_emitter`) plays every one-shot
effect from one capped pool: the pistol's muzzle flash, each bullet impact, and anything a game adds. An effect is an
`EffectDef` resource (a `.tres`, or a sub-resource inside a scene); the emitter plays it where it is told:

```gdscript
var emitter := EffectEmitter.find(self)          # null when the level has none: skip the effect
if emitter != null:
    emitter.play_at(spark_effect, hit_point, hit_normal)   # the effect's +Y along the normal
    emitter.play_on(flash_effect, muzzle_marker)           # out of the marker's -Z, following it
```

- **`EffectDef` (the effect), in the inspector.** Particles: `particles`, a scene of one-shot `CPUParticles3D` or
  `GPUParticles3D` nodes (the root may be one; every one is restarted and the effect lasts as long as the longest).
  Sound: `sound` (an `AudioStreamRandomizer` gives variants), `sound_volume_db`, `sound_bus` (`SFX`),
  `sound_max_distance`. Light: `light_energy` (0 makes none), `light_color`, `light_range`, `light_time` (it fades out
  over it). Timing: `duration` (0 waits for the parts to end by themselves; a number cuts the effect) and
  `max_instances` (4: how many show at once, a newer one takes the oldest's place). Placement: `offset`,
  `rotation_degrees` and `size` (the particles' scale and the light's reach). Every part is optional, and every number
  is read when the effect plays, so a change while the game runs shows in the next play.
- **`EffectEmitter`, in the inspector.** `enabled`, `particles_enabled`, `sounds_enabled` and `lights_enabled` switch
  the whole level's effects; `max_effects` (24) and `web_max_effects` (12, used in the web build and on phones) cap the
  pool; `max_lights` (2) caps the flashes of light at once (past it an effect plays without its light: the
  Compatibility renderer counts every light against its per-object cap); `warm_up_on_start` (on) and `warm_up` are
  [the warm-up](#warm-up). `play_at(effect, point, direction, with_particles, with_sound, size_scale)` and
  `play_on(effect, node, size_scale, with_particles, with_sound)` return the `EffectSlot` that plays (null when nothing
  does); `stop_all()`, `active_count()`, `light_count()` and `slot_count()` read the pool.

## The pool and the flash {#pool-and-flash}

- **The pool.** A slot (`EffectSlot`: the particle nodes, an `AudioStreamPlayer3D` and an `OmniLight3D`, made the first
  time they are needed) is hidden, its light off and its particles stopped while it is free; an effect ends by itself
  (its particles and light and then its sound) and gives the slot back, so a long fight makes no new nodes (a test plays
  200 effects and counts them). When the pool is full the oldest effect is cut for the new one. The emitter does nothing
  while no effect plays (`set_process(false)`). It is built to be cosmetic: made on each machine from what happened,
  never sent over the network.
- **The muzzle flash.** `Weapon.muzzle_flash` (`gameplay/weapon/muzzle_flash.tres`) is an `EffectDef` played on the
  `muzzle` marker for each shot: a star drawn by one shader on a `CPUParticles3D` quad (`assets/shaders/effects/
  flash_star.gdshader`: two flat colours, spikes, camera-facing, additive), a spray of eight short sparks and a
  2.5-energy warm light that lasts 0.06 s. `Weapon.muzzle_flash_enabled` switches it off for that weapon,
  `muzzle_flash_size` resizes it, and another weapon points `muzzle_flash` at its own `EffectDef`. The flash stands at
  the muzzle's position and turns with it for as long as it lasts, and a scaled muzzle does not scale it.
- **Tests and captures.** `tests/gameplay/test_effect_emitter.gd` (placement, following, ending), `test_effect_pool.gd`
  (the cap, reuse, the oldest cut, lights, switches, node counts), `test_effect_exports.gd` (the defaults and every
  live change), `test_muzzle_flash.gd` and `test_muzzle_flash_in_the_map.gd`;
  `tools/capture/muzzle_flash_tour.tscn` films the flash in slow motion with the flash on and then off, and
  `tools/bench/effects_cost.tscn` measures the cost.

## The warm-up {#warm-up}

A weapon registers its `muzzle_flash` and each `ImpactSurface` its effect with the emitter when the level starts
(`warm(effect)`, and the `warm_up` list adds more). Two frames in, once the camera is current, the emitter builds each
slot and plays every effect once, unseen, in front of the camera (the particles at a hundredth of their size, the light
at a hundredth of its energy and forty times its reach, no sound), first with the lights off and then with them on, and
frees the slots again; `warmed` is emitted when it is over. The Compatibility renderer builds a program the first time a
shader is drawn and another for a surface an omni light reaches ([First-use hitches](first-use-hitches.md)), so an
effect first drawn at the first shot stops the frame. `warm_up_on_start` turns it off.

## What it costs {#cost}

Measured with `tools/bench/effects_cost.tscn` (the pistol fires at every chance, at 4 and at 30 shots a second, 300
frames after 90 of warm-up, the character in the map, 1280 x 720, vsync off; Godot 4.7.2, an RTX 5080):

| Run | Desktop Compatibility: frame ms, draw calls | Desktop Forward+: frame ms, draw calls | Web, Chrome on the GPU: frame ms, draw calls |
| --- | --- | --- | --- |
| nothing fired | 1.13, 162 | 0.86, 264 | 5.10, 162 |
| shots, no flash, no impacts, 4 a second | 1.12, 163 | 0.88, 265 | 5.10, 163 |
| the flash, 4 a second | 1.02 to 1.04, 164 | 0.86, 266 | 5.11, 164 |
| flash and impacts, 4 a second | 1.12, 166 | 0.83, 268 | 5.12 to 5.30, 172 |
| shots, no flash, 30 a second | 1.13, 170 | 0.90, 273 | 5.13, 178 |
| flash and impacts, 30 a second | 1.29, 191 | 0.88, 289 | 5.17, 227 |

- **Script cost:** one `play_on` is 11 to 14 microseconds (the pool full, the oldest cut), a step of the pool with three
  effects playing 4.4 to 5 microseconds, and with none 0.5 (and the emitter's `_process` is off then). In the web build
  the same numbers.
- **What shows in a frame:** a flash and its sparks add two to three draw calls and an impact one or two; at 30 shots a
  second with impacts seven slots were busy and the frame grew by 0.15 ms on the desktop (1.13 to 1.29), 0.02 ms in
  Forward+ and 0.06 ms in Chrome. The pool holds the nodes: 538 in the level before a shot, 545 after the first flash,
  and never more than 24 slots (12 on the web) of about four nodes however long the fight.
- **First use is the cost that shows on the web.** With a fresh browser profile each effect's first draw builds programs
  (counted at `linkProgram`): the flash's star and sparks 6 programs and 171 ms, its light (the lit versions of the
  surfaces it reaches) 4 and 185 ms, the first impact (marks, the dust) 5 and 125 ms; the slowest frame of each was 338,
  219 and 161 ms. With the warm-up the star and sparks are 2 programs and 52 ms (slowest frame 64), the light still 4
  and 163 ms (188) and the impact 5 and 120 ms (149): the warm-up removes the flash's own, not the lit programs of the
  character and the pistol or the mark's shader, which a loading screen must draw (follow-up). The desktop built the
  same programs in 0 to 7 ms once its shader cache existed (the very first desktop run had one frame of 274 ms).
- **Software rendering** (headless Chromium on SwiftShader) ran 150 to 170 ms a frame whatever the effect and cannot
  show the difference; only the program counts are the same as on a GPU.
- **Approach:** Measure an effect system with the bench in both renderers and in Chrome on a real GPU, and read the
  slowest frame of the first use and the programs linked then, not only the mean. **Watch out for:** the mean frame of
  every run was within 0.2 ms of the idle one and said the flash was free, while the first flash stopped the web build
  for 338 ms and its light for 219 more, and the 90 frames of warm-up in each run hid those first frames until
  `first_frames_max_ms` read them. Drawing an effect once to warm it builds the program of how it was drawn (a surface
  an omni light reaches is another program): draw it with the lights off and on, and an effect drawn with a light that
  its real use lacks does not warm the real one. **Seen:** gdstudio #888, 2026-11-10.
