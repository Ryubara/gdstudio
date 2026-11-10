# The effect emitter and the muzzle flash

<!-- new section: the 3D Third Person template's one-shot effects (gdstudio #888) and nothing else held how a
     pooled emitter is used or what it costs; the template page holds the short version -->

How the 3D Third Person template plays one-shot effects: the pistol's muzzle flash, each bullet impact and anything a
game adds go through one pooled `EffectEmitter`. Built and measured in Godot 4.7.2 (Windows, an RTX 5080, and the web
export in Chromium); the template's own part is on [the template page](third-person-template.md#effects), the rules
every one-shot effect follows on [Pooled and one-shot effects](one-shot-effects.md#the-rule), the flash's look on
[Shot feedback](shot-feedback.md#muzzle-flash).

One `EffectEmitter` in the level (`Effects` in `main.tscn`, the group `effect_emitter`) plays every one-shot effect from
one capped pool: the pistol's muzzle flash, each bullet impact, and anything a game adds. An effect is an `EffectDef`
resource (a `.tres`, or a sub-resource inside a scene); the emitter plays it where it is told:

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
  Compatibility renderer counts every light against its per-object cap); `warm_up` lists effects whose slots are built
  when the level starts. `play_at(effect, point, direction, with_particles, with_sound, size_scale)` and
  `play_on(effect, node, size_scale, with_particles, with_sound)` return the `EffectSlot` that plays (null when nothing
  does); `stop_all()`, `active_count()`, `light_count()` and `slot_count()` read the pool.
- **The pool.** A slot (`EffectSlot`: the particle nodes, an `AudioStreamPlayer3D` and an `OmniLight3D`, made the first
  time they are needed) is hidden, its light off and its particles stopped while it is free; an effect ends by itself
  (its particles and light and then its sound) and gives the slot back, so a long fight makes no new nodes (a test plays
  200 effects and counts them). When the pool is full the oldest effect is cut for the new one. The emitter does nothing
  while no effect plays (`set_process(false)`). It is built to be cosmetic: made on each machine from what happened, never
  sent over the network.
- **The muzzle flash.** `Weapon.muzzle_flash` (`gameplay/weapon/muzzle_flash.tres`) is an `EffectDef` played on the
  `muzzle` marker for each shot: a star drawn by one shader on a `CPUParticles3D` quad (`assets/shaders/effects/
  flash_star.gdshader`: two flat colours, spikes, camera-facing, additive), a spray of eight short sparks and a 2.5-energy
  warm light that lasts 0.06 s. `Weapon.muzzle_flash_enabled` switches it off for that weapon, `muzzle_flash_size`
  resizes it, and another weapon points `muzzle_flash` at its own `EffectDef`. The flash stands at the muzzle's position
  and turns with it for as long as it lasts, and a scaled muzzle does not scale it.
- **Tests and captures.** `tests/gameplay/test_effect_emitter.gd` (placement, following, ending), `test_effect_pool.gd`
  (the cap, reuse, the oldest cut, lights, switches, node counts), `test_effect_exports.gd` (the defaults and every
  live change), `test_muzzle_flash.gd` and `test_muzzle_flash_in_the_map.gd`;
  `tools/capture/muzzle_flash_tour.tscn` films the flash in slow motion with the flash on and then off, and
  `tools/bench/effects_cost.tscn` measures the cost.
- **Cost.** MEASUREMENTS
