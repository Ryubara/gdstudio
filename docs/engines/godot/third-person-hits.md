# Hit zones and shot deaths in 3D Third Person

<!-- new section: a shot met one capsule, `hit()` only stunned it and nothing died of a shot (gdstudio #876); no page
     said how a shot finds a body part, what a hit record holds or how the body answers it -->

## The components {#component}

A shot lands on a body part and the body answers it on each peer: a headshot snaps the head back and, when it kills,
the ragdoll falls along the shot; a hit that does not kill makes the hit part flinch while the legs keep their clip; a
shot into a body already lying pushes the bone it meets and leaves an impact mark on it. Everything is in
`gameplay/character/character_dressed.tscn` (so every character and the player have it) and the scripts are
`gameplay/hit_zones/` (`HitZones`, `HitZone`), `gameplay/character/hit_reaction.gd` and, in the synced
`addons/gds_game/hits/`, `HitRecord` and `Health` ([below](#health)).

- **How a shot finds the part (two steps).** The `Projectile` flies against the character's capsule as it does against
  anything. When it touches a capsule tagged by a `HitZones` (the metadata `hit_zones`), it asks
  `HitZones.shot(collider, point, direction, damage, strength, source, centre)`: the zones are put on their bones of the
  animated skeleton (`follow_bones()`) and a ray along the shot's own line, from the projectile's centre through the
  capsule (`ray_length`, 1.2 m), looks for the first zone with `PhysicsLayers.HIT_ZONE_MASK`. A zone met: a
  `HitRecord` goes to the character's `take_hit()`. None: the shot passed between the parts (beside the waist, between
  the legs), takes the capsule as an exception and flies on in the same tick. A lying body is met on its ragdoll bones
  (they carry the same tag while limp), and the record names the bone.
- **Where a weapon aims on a character.** The aim ray asks the same two steps: `HitZones.aimed_point(point, along)`
  answers the point on the part the ray meets past the capsule, or `Vector3.INF` when it passes between the parts, and
  `Weapon.aim_point` then goes on to what is behind the body (with the zones off it is the capsule's point). The shot
  leaves the muzzle toward that point, so a close shot lands on the part under the crosshair, not beside it
  (gdstudio #1251, [Shooting](third-person/shooting.md#crouch-aim-shoot)).
- **Why two steps.** The zones move only for a shot that reached a capsule, never every frame: they cost nothing while
  nobody shoots (the numbers are below). The price: a part held outside the capsule (an arm stretched out to aim) is
  not hit, since the capsule is the first test.
- **The record.** `HitRecord`: `damage` (the zone's multiplier applied), `zone`, `bone`, `point`, `direction`,
  `strength` (the shot's impulse, N·s), and three local fields never sent (`source`, `knockback`, `killed`).
  `encode()` packs the sent part in about 40 bytes (`decode()` reads it back and refuses a short or non-finite one). It
  is all a game's networking sends for a hit: a peer gives it to its own copy (`take_hit(record)`) and makes the
  damage, the flinch, the push and the mark itself, so no ragdoll or flinch is ever sent (kit #906 carries it).
- **Health.** `Character.take_hit(record)` gives the record to the character's `Health` child ([below](#health)), says
  `took_hit` and `health_changed`, and when the health reaches zero dies (`die(record)`), goes limp and then says
  `hit_received(record)` with `killed` set. `health` and `max_health` on the character read the `Health` node's `value`
  and `max_value` (read only: a game sets the `Health` node). `hit(amount, source)` is still there: a blow with no point
  that also stops and throws the character (`hit_stun_time`, `knockback_speed`), as before. The hit clip plays over the
  whole body standing and over the upper body only crouched, lying or sliding (`HitLayer`), so a low body stays down,
  and with a weapon held it leaves the arms to the weapon, held up through the stun
  ([one action state for every body](animation-tree.md#one-action-state-for-every-body)). A dead character takes no
  damage, but its `hit_received` still fires (the lying-body push). Getting up gives the health back, and `die()` with
  no record sets it to 0. The HUD's health part reads `health` and `max_health` and shows them.
- **The reaction.** `HitReaction` listens to `hit_received`. A record that killed pushes the hit bone at the hit point
  along the shot by `death_push` times its strength; a hit on a lying body by `lying_push`. A hit that does not kill
  starts a flinch: the hit body and every body hanging from it go physical (`physical_bones_start_simulation` with that
  list, never a leg; a hit on the pelvis or a leg starts from `spine_01`), pushed at its middle by `flinch_push` (at
  most `flinch_most_speed`), shown at `flinch_strength` through the simulator's `influence`, held for `flinch_hold` of
  `flinch_time` and blended back to the clip, then the bones stop. The bodies it leaves out are put on the clip's pose
  in the server, at rest and off every layer, and the ragdoll's extra joints go for the flinch ([A partial
  ragdoll](ragdoll.md#partial)). A death during a flinch hands the whole skeleton to the ragdoll. The marks shots left
  on the bones go when the body gets up (`Impacts.clear_marks_on(simulator)`).

- **Approach:** Push a body by a speed, not only by the shot's strength: the kill's and the lying body's push land on
  the hit body's middle and give it at most `push_most_speed` (the impulse limited to `mass * push_most_speed`).
  **Watch out for:** the same 40 N·s is a nudge to the 14 kg chest and a launch to a 1 kg forearm (26 m/s) or a shin
  (12 m/s); a rifle sprays limbs and keeps firing into the falling body. Measured per weapon, one kill on each part of
  a standing target (pistol 40 N·s, rifle 25 N·s, `death_push` 1.5): the fastest bone was 5 to 6 m/s on the head,
  chest, pelvis and thigh for both, and 10 to 26 m/s on an arm, forearm or shin before the cap, under 9 after.
  **Seen:** gdstudio #1343, 2026-11-12 (`test_death_push.gd`).

### The inspector {#inspector}

- **On `HitZones`** (a `StaticBody3D` on layer 6, Hit Zones, mask none): `receiver` (the character), `model` (the slot
  whose skeleton the zones follow), `ragdoll`, `enabled` (off: a shot on the capsule hits the whole body, no zone and no
  multiplier) and `ray_length`.
- **On each `HitZone`** (a `CollisionShape3D` under it; size its shape in the inspector): `zone` (its name), `bone`,
  `offset` (in the bone's frame, Y along the bone; the node's own transform is overwritten), `damage_multiplier` and
  `enabled`. The eleven: `head` (sphere, 3.0), `chest` and `pelvis` (1.0), `arm_l`, `arm_r`, `forearm_l`, `forearm_r`
  (0.6), `thigh_l`, `thigh_r`, `shin_l`, `shin_r` (0.7); the forearm capsules reach over the hands, the feet have none.
- **On `HitReaction`**: `death_push` (1.5), `push_most_speed` (5 m/s: the most a kill's or a lying body's push
  gives the body it hits, on its middle), `lying_push` (0.5), `flinch_enabled`, `flinch_push` (0.6),
  `flinch_most_speed` (3 m/s), `flinch_strength` (0.85), `flinch_time` (0.45 s), `flinch_hold` (0.25).
- **On the character's `Health` node** (in `character.tscn`): `enabled` (off: hits still flinch and push but take
  nothing), `max_value` (100) and the rest of [the component](#health). **On the `WeaponDef`** (`pistol.tres`):
  `damage` (34: three chest shots, one headshot), passed to the projectile's `damage` and to a hitscan shot's or a
  blow's record.

### What it costs {#cost}

`tools/bench/hit_zones_bench.tscn` (1, 4 and 10 `character_dressed.tscn` in their idle clip; `hit_zones_bench.py`
runs the web export in headless Chrome under `gds quiet`). A shot is one second test on a chest; `follow` is one
`follow_bones()`, what each character would pay every tick if the zones followed the skeleton all the time; the frame
is the tree's `physics_frame` to its next `process_frame` (the physics callbacks and the server's step, not the wait).

| | shot | follow | frame, standing | frame, all flinching |
| --- | ---: | ---: | ---: | ---: |
| Desktop, 1 / 4 / 10 characters | 14 to 22 µs | 6 to 10 µs | 0.16 / 0.30 / 0.54 ms | 0.18 / 0.34 / 0.63 ms |
| Chrome, 1 / 4 / 10 | 23 to 29 µs | 9 to 12 µs | 0.18 / 0.37 / 0.71 ms | 0.31 / 0.56 / 1.09 ms |
| Chrome at a 4x CPU throttle, 1 / 4 / 10 | 139 to 174 µs | 57 to 89 µs | 1.16 / 2.32 / 3.58 ms | 1.48 / 2.72 / 6.36 ms |

The budget the task set: a shot's second test under 50 µs on the desktop and in Chrome, the zones nothing a frame, a
flinching body under 0.05 ms a frame in Chrome (measured 0.04). The zones following every tick would have cost 0.1 ms
a frame for ten characters in Chrome and 0.8 ms at the throttle, which is why they do not. Ten bodies flinching at once
for good is the worst case and the throttled web build pays 2.8 ms for it; the flinch is a local cosmetic, so a game
short of time turns `flinch_enabled` off for far characters. Desktop: three headless runs; browser: one run each, on a
machine other agents were using.

### Tests and captures {#tests}

`tests/gameplay/test_hit_zones.gd` (each zone hit by a real projectile and its damage scaled, health to zero and the
death, a shot between the parts flying on, zones met by nothing but the second test, the record on the wire, the
pins), `test_hit_reaction.gd` (the headshot and body-shot pushes, the flinch and its return in its time, a death during
a flinch, a shot on a lying body pushing its bone and leaving a mark that rides it and goes on getting up),
`test_physics_layers_meet.gd` (a living body has no bone in the world). The fixture is `tests/fixtures/hit_range.gd`.
The zones' shapes are sized on the template's two prototype bodies (kit #1187, `tools/mannequin/measure_segments.gd`;
[the bodies](third-person/character.md#mannequins)). `tools/capture/hit_tour.tscn` films it from the player's camera
(`HIT_MODEL=male` for the male body):
`gds capture frames --project game --scene res://tools/capture/hit_tour.tscn --seconds 26`.
`tools/capture/enemy_pose_tour.tscn` films an armed body on the enemy's mannequin taking chest shots while it aims,
beside one that fires dry and reloads (`--seconds 9`); `tools/soak/ai_pose_log.tscn` prints every AI character's
state, locomotion node and layers (`POSE` lines) through a seeded soak, to trace a pose seen in play to its clip.

- **Approach:** Run a shot's second test along the projectile's own line (its centre at the touch), not from the
  contact point. **Watch out for:** a sphere that touches a curved capsule touches it off its centre line, so a ray
  from the contact point missed a 6 cm upper arm the shot was aimed at and found the chest behind it; the test that
  shoots every zone from the side that sees it first caught it. **Seen:** gdstudio #876, 2026-11-10.
- **Approach:** Aim a capture's camera once a drawn frame (`_process`) and turn by a share of the error. **Watch out
  for:** at a capture's 10 frames a second each frame runs six physics ticks while the camera moves once, so an aim
  loop in `_physics_process` turned six times too far and swung about the target for the whole clip, firing nothing,
  while the same loop converged headless at 60. **Seen:** gdstudio #876, 2026-11-10 (`hit_tour.gd`).

## The Health component {#health}

<!-- new section: health was a number on the character and a target counted hits of its own, and a shot called
     `take_shot` by its name; nothing gave an AI character (#963), a target and a prop one way to take harm (gdstudio
     #925) -->

`Health` (`addons/gds_game/hits/health.gd`, synced into every game) is a node that anything which can be hurt carries:
`character.tscn` has one (so the player and every AI character built on `Character` do), `target.tscn` has one, and a
crate or a barrel takes shots once one is added under it. A shot finds it by type, `Health.of(body)` (the body itself
or its first child that is one), never by a method name; a body without one takes no harm, and its script says so in a
configuration warning (the character, the target). The `Projectile` gives a record of its `damage` to the `Health` of
what it touched when that has no `HitZones`; `HitZones` hands its record to a `Character`'s `take_hit()`, or to the
`Health` of any other receiver.

- **API** (for code that hurts or reads: an AI's brain, a HUD, a network peer). `apply(hit: HitRecord) -> float` takes
  `hit.damage` off `value` (when `enabled`, not `invulnerable` and alive), sets `hit.killed` on the hit that reaches
  zero and returns what it took. `heal(amount)`, `kill(hit = null)`, `reset()` (full again; `revived` after zero),
  `is_dead()`, `fraction()`, `value` (settable: zero dies, above zero after zero revives), `max_value`.
- **Signals**, in the order a hit says them: `changed(value, max_value)`, `damaged(amount, hit)`, `died(hit)` (once a
  life; `hit` null for `kill()` or a value set to zero), `flinched(hit)` (a hit that did not kill and is at least
  `flinch_threshold`), then `hit_taken(hit)` for every hit, also when it took nothing (off, invulnerable, already dead:
  a lying body is still pushed). `revived` after `reset()` from zero.
- **The inspector:** `enabled`, `max_value` (100; lowering it lowers the value), `invulnerable`; Regeneration:
  `regeneration_per_second` (0, none) and `regeneration_delay` (0 s, the wait after the last damage); Flinch:
  `flinch_threshold` (0: every hit that does not kill). The target's `Health` has `max_value` 1 (any shot drops it;
  60 takes two of the weapon's 34).
- **What it costs.** Nothing a frame unless it regenerates: `_physics_process` runs only while
  `regeneration_per_second` is above zero and the value is below the maximum and above zero, and stops when it is full
  or dead. A hit is a few comparisons and signals.
- **Networking.** The replicated value is one integer: `wire_value()` (rounded up, so a body alive on one peer is alive
  on the other) and `set_wire_value(n)` on the peer. A flinch, the blood and the ragdoll are never sent; each peer makes
  them from the `HitRecord` (about 40 bytes) it is given.
- **An AI character** ([#963](https://github.com/Ryubara/gdstudio/issues/963)) gets its health from the `Health` node
  of `character.tscn`: listen to `damaged` to turn toward `hit.source`, to `flinched` to stop and react, and to
  `died` (the `Character` already dies into its ragdoll on it); tune `max_value`, `regeneration_*`, `invulnerable` and
  `flinch_threshold` per profile on the node, never copy the player's numbers into the AI's script.
- **Tests:** the component alone in the kit's `godot/tests/gds_game/test_health_alone.gd` (death once, invulnerable,
  off, the threshold, regeneration waiting its delay and no per-frame work while off, the wire, the pins); in the
  template `tests/gameplay/test_hit_and_interact_components.gd` (a target and a character both take a real shot
  through it, a target or character without it warns and takes nothing, no method-name lookup left in `gameplay/`).
