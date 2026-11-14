# Physics layers

<!-- new section: every body of the templates sat on layer 1 and areas told a character from a wall by class in
script; no page said which layers a GDStudio game has, what each mask lists, or why (gdstudio #924) -->

Godot gives every `CollisionObject3D` a `collision_layer` (what it is) and a `collision_mask` (what it looks for); two
objects meet when either one's mask lists the other's layer, and an `Area3D` or a ray hears only of what its own mask
lists ([Physics introduction](https://docs.godotengine.org/en/stable/tutorials/physics/physics_introduction.html#collision-layers-and-masks)).
A layer is named under Project Settings > Layer Names > 3D Physics, which writes `[layer_names]` into `project.godot`
and labels the inspector's layer grid.

## The template layers {#template-layers}

3D Blank's `project.godot` names the eight layers (3D Third Person's adds only its own keys and gets them from it), and
`core/physics_layers/physics_layers.gd` (`PhysicsLayers`, in 3D Blank, so every template has it) holds them as bits,
so code and the inspector say the same thing. The constants script moves to the synced gameplay addon
(`addons/gds_game/physics/physics_layers.gd`) with kit #923's second step; the names stay in each game's `project.godot`.

| Layer | Name | Constant | On it | Mask (constant) |
| --- | --- | --- | --- | --- |
| 1 | World | `WORLD` | floors, walls, `ProtoBlock`s, doors, moving platforms, targets | none needed (static) |
| 2 | Characters | `CHARACTERS` | the player's capsule (later AI and networked bodies) | World, Props (`CHARACTER_MASK`) |
| 3 | Projectiles | `PROJECTILES` | shots in flight (`projectile.tscn`) | World, Characters, Props, Ragdoll, Shot Hulls (`SHOT_MASK`); then Hit Zones inside a capsule it met (`HIT_ZONE_MASK`) |
| 4 | Props | `PROPS` | `PhysicsProp` (pushed crates, balls) | World, Characters, Props (`PROP_MASK`) |
| 5 | Ragdoll | `RAGDOLL` | the bones of a limp body (`CharacterRagdoll`) | World, Props, Ragdoll (`RAGDOLL_MASK`) |
| 6 | Hit Zones | `HIT_ZONES` | the `HitZones` body of a character (its parts, [Hit zones](third-person-hits.md)) | none (scanned only by a shot's second test) |
| 7 | Sensors | `SENSORS` | `Pickup`, `TriggerZone`, a door's `Sensor`, an `Interactable` | Characters (`CHARACTER_SENSOR_MASK`); a trigger zone Characters and Props (`TRIGGER_MASK`); an `Interactable` none (an `Interactor`'s query on `SENSORS` finds it) |
| 8 | Shot Hulls | `SHOT_HULLS` | a living character's `ShotHull`, a capsule a little wider and taller than its own that only shots meet, on this layer only while a shot near it has armed it ([the hull](third-person-hits.md#shot-hull)) | none (only `SHOT_MASK` lists it; a shot's mark and the network's hit probe use `SURFACE_MASK`, without it) |

Rays and other masks: the camera's spring arm (`PlayerCamera.wall_mask`) is World and Props (`CAMERA_MASK`); the
weapon's aim ray (`Weapon.aim_mask`) is `SHOT_MASK`, so the crosshair's point is on what the shot will hit; the
player's ground and ceiling probes use the player's own mask; the player's `platform_floor_layers` is World and Props
(the default, every layer, would let a body standing on a bone or a sensor take its velocity).

Projectiles (3) and ragdoll bones (5) kept the numbers they had before the layers had names (4 and 16 as bits).

- **Approach:** Give every body the layer of what it is and every area the mask of what it senses, and keep the class
  test (`Pickup.characters_only`, `TriggerZone.counts`, the door's `CharacterBody3D` check) behind the mask as a second
  condition, for a game with its own layers. Prove both: a suite counts `body_entered` callbacks (a pickup against a
  wall gets none for the wall) and a suite sets the mask wider to show the class test still keeps a crate out.
  **Watch out for:** with every body on layer 1 every area heard of the floor and walls around it (#845, #848); the
  class test hid that from the game, not from the physics step. A test body made with `.new()` is on layer 1, the
  level: put a `CharacterBody3D.new()` on Characters or a pickup never hears of it.
  **Seen:** gdstudio #924, 2026-11-10 (`test_components_among_blocks.gd`, `test_physics_layers_meet.gd`).
- **Approach:** Keep a test that reads every layer-grid value of every scene (each node's properties with the hint
  `PROPERTY_HINT_LAYERS_3D_PHYSICS`, scripts' exports included) and fails on a bit the project does not name
  (`tests/core/test_physics_layers.gd`). **Watch out for:** `CharacterBody3D.platform_floor_layers` defaults to every
  layer (`4294967295`), so the first run named 25 unnamed layers on the player and the projectile; set it in the
  scene to the layers a body may ride. **Seen:** gdstudio #924, 2026-11-10.
- **Approach:** When a layer joins `SHOT_MASK`, or a new body takes a layer it holds, list the code that reads what a
  shot-mask ray met (`grep -rn "SHOT_MASK\|aim_mask\|hitscan_mask\|keep_aim_layers" gameplay`: the weapon's aim ray,
  `WeaponDef.hitscan_mask`, the camera's `aim_point_mask` and its aimed-point keep list `keep_aim_layers`, the network's
  hit probe in `net_hits.gd`) and give each a case for the new layer. **Watch out for:** nothing lists those readers, so
  a ray meets the new layer while a reader does not know it: the camera's ray met a character's Shot Hull, which
  `keep_aim_layers` did not count, and an aimed shoulder swap at a character stopped keeping its point (fixed with
  `ShotHull.ray_as_shot`, [the shot hull](third-person-hits.md#shot-hull)). **Seen:** gdstudio PR #1459, 2026-11-14
  (`test_camera_swap_target.gd`).

## Characters do not block each other {#characters-do-not-block}

<!-- new section: the issue asked for the choice with its reason written down; it is a setting, not an accident -->

`CHARACTER_MASK` leaves Characters out, so two characters walk through each other. The reason is networking: a client
draws the other players as puppets with no collision, so a server whose bodies stop at each other ends metres from
the client ([The two worlds](multiplayer.md#the-two-worlds-must-hold-the-same-solid-things), Deadnight #760). A game
without networking that wants solid characters adds Characters to the player's Collision > Mask in `player.tscn`; a
shot still meets a character either way (Characters is in `SHOT_MASK`).

- **Approach:** Decide whether bodies block each other before the first networked build, write the reason beside the
  constant, and test it with a real character walking through another body on Characters
  (`test_physics_layers_meet.gd`). **Watch out for:** Deadnight's bodies on layer 1 with a mask of 1 and 2 stopped at
  a teammate on the server and not on the client. **Seen:** Deadnight #760, 2026-11-03; gdstudio #924, 2026-11-10.

## Shots meet ragdoll bones {#shots-meet-bones}

<!-- new section: before #924 a shot passed through a dead body; the maintainer decided on 2026-11-10 (#876) that
shots hit the bones of a dead body, and the layer change is where that starts -->

`SHOT_MASK` lists Ragdoll, so a shot (and the aim ray) stops at a limp bone instead of passing through the body.
While the character is alive its bones are out of the physics world (layer and mask 0 in the server: the engine does
it when a bone stops simulating, and `CharacterRagdoll` does it for bones that never did), so a shot past the capsule
still reaches the wall behind and the shooter's own shots and aim ray never meet its own bones. The bone takes the
shot's mark and push ([Hit zones](third-person-hits.md)). `SHOT_MASK` leaves Hit Zones out: a living character is met
at its capsule, and only then are its zones looked for (`HIT_ZONE_MASK`).

- **Approach:** Prove a shot meets a dead body with a real death: kill a `Player` in an arena, wait for it to lie
  still, fire a real `Projectile` at a bone's position and read the collider of `impacted` (`PhysicalBone3D`); fire
  past a living one's capsule at hand height and read the wall. **Watch out for:** the chest bone is `spine_03` (the
  bodies are `CharacterRagdoll.BODIES`: `pelvis`, `spine_01`, `spine_03`, `Head`, ...), not `spine_02`. **Seen:**
  gdstudio #924, 2026-11-10.
- **Approach:** Prove that a living body has no bone in the world with a ray of `SHOT_MASK` at each bone of a
  character that never died (`test_a_living_body_that_never_died_has_no_bone_in_the_world`). **Watch out for:** 4.7.2
  zeroes a `PhysicalBone3D`'s server layer only when it stops simulating; a bone made with its layer set and never
  limp stays a static body on that layer, following the skeleton a tick late, so a ray at a living head met the
  `Head` bone. The #924 test fired beside the capsule at hand height, where no bone was, and passed. Fix: after
  setting the layers, `PhysicsServer3D.body_set_collision_layer(rid, 0)` (and the mask) for every bone not simulating.
  **Seen:** gdstudio #876, 2026-11-10 (found by the hit-zone suite's ray of every other mask through the head).
