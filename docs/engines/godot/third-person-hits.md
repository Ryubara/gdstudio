# Hit zones and shot deaths in 3D Third Person

<!-- new section: a shot met one capsule, `hit()` only stunned it and nothing died of a shot (gdstudio #876); no page
     said how a shot finds a body part, what a hit record holds or how the body answers it -->

## The components {#component}

A shot lands on a body part and the body answers it on each peer: a headshot snaps the head back and, when it kills,
the ragdoll falls along the shot; a hit that does not kill makes the hit part flinch while the legs keep their clip; a
shot into a body already lying pushes the bone it meets and leaves an impact mark on it. Everything is in
`gameplay/character/character_dressed.tscn` (so every character and the player have it) and the scripts are
`gameplay/hit_zones/` (`HitZones`, `HitZone`, `HitRecord`) and `gameplay/character/hit_reaction.gd`.

- **How a shot finds the part (two steps).** The `Projectile` flies against the character's capsule as it does against
  anything. When it touches a capsule tagged by a `HitZones` (the metadata `hit_zones`), it asks
  `HitZones.shot(collider, point, direction, damage, strength, source, centre)`: the zones are put on their bones of the
  animated skeleton (`follow_bones()`) and a ray along the shot's own line, from the projectile's centre through the
  capsule (`ray_length`, 1.2 m), looks for the first zone with `PhysicsLayers.HIT_ZONE_MASK`. A zone met: a
  `HitRecord` goes to the character's `take_hit()`. None: the shot passed between the parts (beside the waist, between
  the legs), takes the capsule as an exception and flies on in the same tick. A lying body is met on its ragdoll bones
  (they carry the same tag while limp), and the record names the bone.
- **Why two steps.** The zones move only for a shot that reached a capsule, never every frame: they cost nothing while
  nobody shoots (the numbers are below). The price: a part held outside the capsule (an arm stretched out to aim) is
  not hit, since the capsule is the first test.
- **The record.** `HitRecord`: `damage` (the zone's multiplier applied), `zone`, `bone`, `point`, `direction`,
  `strength` (the shot's impulse, N·s), and three local fields never sent (`source`, `knockback`, `killed`).
  `encode()` packs the sent part in about 40 bytes (`decode()` reads it back and refuses a short or non-finite one). It
  is all a game's networking sends for a hit: a peer gives it to its own copy (`take_hit(record)`) and makes the
  damage, the flinch, the push and the mark itself, so no ragdoll or flinch is ever sent (kit #906 carries it).
- **Health.** `Character.take_hit(record)` takes the damage from `health`, says `took_hit` and `health_changed`, and at
  zero calls `die(record)`, which goes limp and then says `hit_received(record)` with `killed` set. `hit(amount,
  source)` is still there: a blow with no point that also stops and throws the character (`hit_stun_time`,
  `knockback_speed`), as before. A dead character takes no damage, but its `hit_received` still fires (the lying-body
  push). Getting up gives the health back, and `die()` with no record sets it to 0. The HUD's health part reads
  `health` and `max_health` and shows them.
- **The reaction.** `HitReaction` listens to `hit_received`. A record that killed pushes the hit bone at the hit point
  along the shot by `death_push` times its strength; a hit on a lying body by `lying_push`. A hit that does not kill
  starts a flinch: the hit body and every body hanging from it go physical (`physical_bones_start_simulation` with that
  list, never a leg; a hit on the pelvis or a leg starts from `spine_01`), pushed by `flinch_push`, shown at
  `flinch_strength` through the simulator's `influence`, held for `flinch_hold` of `flinch_time` and blended back to
  the clip, then the bones stop. A death during a flinch hands the whole skeleton to the ragdoll. The marks shots left
  on the bones go when the body gets up (`Impacts.clear_marks_on(simulator)`).

### The inspector {#inspector}

- **On `HitZones`** (a `StaticBody3D` on layer 6, Hit Zones, mask none): `receiver` (the character), `model` (the slot
  whose skeleton the zones follow), `ragdoll`, `enabled` (off: a shot on the capsule hits the whole body, no zone and no
  multiplier) and `ray_length`.
- **On each `HitZone`** (a `CollisionShape3D` under it; size its shape in the inspector): `zone` (its name), `bone`,
  `offset` (in the bone's frame, Y along the bone; the node's own transform is overwritten), `damage_multiplier` and
  `enabled`. The eleven: `head` (sphere, 3.0), `chest` and `pelvis` (1.0), `arm_l`, `arm_r`, `forearm_l`, `forearm_r`
  (0.6), `thigh_l`, `thigh_r`, `shin_l`, `shin_r` (0.7); the forearm capsules reach over the hands, the feet have none.
- **On `HitReaction`**: `death_push` (1.5), `lying_push` (0.5), `flinch_enabled`, `flinch_push` (0.6),
  `flinch_strength` (0.85), `flinch_time` (0.45 s), `flinch_hold` (0.25).
- **On the `Character`**, the group Health: `health_enabled` (off: hits still flinch and push but take nothing) and
  `max_health` (100). **On the `Weapon`**: `projectile_damage` (34: three chest shots, one headshot), passed to the
  projectile's `damage`.

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
`tools/capture/hit_tour.tscn` films it from the player's camera (`HIT_MODEL=male` for the other mannequin):
`gds capture frames --project game --scene res://tools/capture/hit_tour.tscn --seconds 26`.

- **Approach:** Run a shot's second test along the projectile's own line (its centre at the touch), not from the
  contact point. **Watch out for:** a sphere that touches a curved capsule touches it off its centre line, so a ray
  from the contact point missed a 6 cm upper arm the shot was aimed at and found the chest behind it; the test that
  shoots every zone from the side that sees it first caught it. **Seen:** gdstudio #876, 2026-11-10.
- **Approach:** Aim a capture's camera once a drawn frame (`_process`) and turn by a share of the error. **Watch out
  for:** at a capture's 10 frames a second each frame runs six physics ticks while the camera moves once, so an aim
  loop in `_physics_process` turned six times too far and swung about the target for the whole clip, firing nothing,
  while the same loop converged headless at 60. **Seen:** gdstudio #876, 2026-11-10 (`hit_tour.gd`).
