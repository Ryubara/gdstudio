# Bullet impacts in 3D Third Person

<!-- new section: the template page passed its size limit (gdstudio #888), so the impacts' inspector list moved here from
     third-person-template.md#impacts; written for #875, the research and the route are in
     [Bullet impacts and marks](shot-feedback.md#impact-marks) -->

## The component {#component}

A shot that lands tells the level's `Impacts` node (`world/world.tscn`; the group `impacts`, so no path): it makes a
mark on the body, bursts the surface's effect and plays its sound. A mark is a flat quad on the body it hit, so it goes
where a pushed crate or a moving platform goes and is freed with it; there is no `Decal` (Compatibility, which the web
build uses, does not draw one). `Impacts.impact(collider, point, normal)` is the one call, so a game's own weapon, a
grenade or a ray gun reuses it.

- **The inspector, on `Impacts`.** Marks: `marks_enabled`, `max_marks` (64; the oldest goes first, a lower number
  trims at once), `mark_lifetime` (30 s, **0 keeps a mark**), `mark_fade_time` (4 s, the end of the life it fades
  over), `mark_material` (the material of every mark, a `ShaderMaterial` with a hole and a ring, or a texture: its
  `use_texture` and `mark_texture`), `mark_size` (0.12 m), `size_variation` (0.3), `random_rotation`,
  `surface_offset` (4 mm) and `random_seed`. Effects: `effects_enabled` and `sounds_enabled`. Surfaces:
  `default_surface`. Every one is read when used: a change shows in the next hit (marks already placed keep their
  look; `max_marks` and `mark_lifetime` also act on them at once).
- **One node a surface.** Under `Impacts/Surfaces` are `Default`, `Wood`, `Metal` and `Target`, each an
  `ImpactSurface` with `surface_name`, `leaves_mark` (off for the target's board, which tips over), `mark_material`
  (empty: the `Impacts`'), `mark_scale` and `effect`, an `EffectDef` (a one-shot `CPUParticles3D` scene and a
  three-variant `sound` on `SFX`) that the level's `EffectEmitter` plays ([Effects](third-person-template.md#effects));
  its `max_instances` is how many hits of the surface can show and sound at once. The slot plays the sound's takes
  decoded once to PCM (`DecodedSounds`), so a hit's sound starts in a few microseconds, not the 300 of an Ogg take
  ([Audio: starting sounds](audio.md#starting-sounds)). Add a node and a name for a new
  surface (`glass`, `flesh`); the default is what a hit gets when the body says nothing or says a name no surface has.
- **Which surface a body is.** The metadata `surface` on the body or any node above it (Inspector, Node, Metadata,
  Add: a name), or a group of that name; the nearest wins. `physics_prop.tscn` says `wood`,
  `moving_platform.tscn` `metal`, `target.tscn` `target`; the map's floor and walls are untagged and so the default.
- **On or off per weapon or projectile.** `WeaponDef.impacts` (its shots land without a trace when off) and
  `Projectile.impact_effects` (the projectile scene's own, for a game with its own projectile); a shot leaves an
  impact when both are on.
- **What takes no mark.** A `CharacterBody3D` (a living character's capsule; the effect and sound still play). A ragdoll
  bone takes one and carries it as the body moves, and `clear_marks_on(node)` takes off every mark on a node or under
  it: the character's `HitReaction` clears the bones when the body gets up ([Hit zones](third-person-hits.md)).
- **Tests and captures.** The scripts alone: the kit's `godot/tests/gds_game/test_impacts_alone.gd`. In the template:
  `tests/gameplay/test_impacts.gd`, `test_impact_marks.gd`, `test_impact_surfaces.gd`,
  `test_impact_effects.gd`, `test_impacts_exports.gd`, `test_impacts_in_the_map.gd` and
  `tests/audio/test_impact_sounds.gd` (real projectiles in a small arena, and in the map);
  `tools/capture/impacts_tour.tscn` plays the pistol through a wall, a pushed cube and the fade (`gds capture frames`,
  and `--rendering-method gl_compatibility` for the web look). The sounds are made by `tools/audio/impact_sounds.py`
  (synthesised, MIT).
