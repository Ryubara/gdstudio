# gameplay

One folder per feature: `gameplay/<feature>/`, holding the feature's scripts, scenes and tuning resources together
(`player/player.gd`, `player/player.tscn`, `player/player_tuning.tres`). A scene with a script shares its name and
folder.

- Split a feature when a folder passes about 30 scripts with clear clusters.
- May use `core/` and `world/`; never `ui/`.

The template has a character and the map's components:

- `character/`: the character whoever drives it (`Character` and its scenes `character.tscn`, the body alone, and
  `character_dressed.tscn`, with its model; `CharacterTuning`, `CharacterAnimation`, `CharacterRagdoll`, `Footsteps`,
  `Interactor`, `StepClimber`, `CharacterClips`, `CharacterController`, `CharacterState`).
- `ai/`: the AI characters' base (`AiCharacter`, `ai_character.tscn`: the dressed character driven by an
  `AiController`), what kind each is (`AiProfile`, `profiles/grunt.tres`, `ally.tres`, `civilian.tres`), and the
  `AiDirector` (a node of `world/world.tscn`) that steps them, runs their thinks and sets their tiers within one
  `AiBudget` a tick; `AiSituation` is what a character believes is going on. `ai/relations/` says who is hostile to
  whom: the `AiRelations` table (`ai_relations.tres`, its `AiFaction` rows and `AiRelationEvent` events), the level's
  `AiFactions` (a node of `world/world.tscn`) and an `AiFactionMember` on each character and the player.
- `player/`: the human's character on top of it (`Player`, `player.tscn`, its `PlayerInput`, `PlayerCommand`,
  `PlayerCamera`). The numbers a developer tunes are in `player_tuning.tres`.
- `weapon/`, `projectile/`, `target/`: a weapon is a `WeaponDef` resource (`pistol.tres`, `fists.tres`: its numbers,
  magazine and reserve, reload, clips and sounds); a `Weapon` fires the one it holds (pooled `Projectile` spheres, a
  hitscan ray or a blow) toward the crosshair and counts its ammunition, a `WeaponLoadout` switches between the slots
  and the empty hands, and a `Target` falls over when its `Health` runs out. They work with any model: a definition
  names the model node it shows and its muzzle marker under the character's `Model` slot. `rifle.tres` is the
  automatic hitscan rifle; `TwoHandHold` (`two_hand_hold.tscn`, the rifle's `rifle_held.tscn`) holds a long gun with
  both hands by IK where the clips have no pose for it. `WeaponLoadout.give()` adds a weapon at run time.
- `hit_zones/`: `HitZones` (a body on the Hit Zones layer holding the `HitZone` shapes, eleven body parts that follow
  the skeleton when a shot needs them). A `Projectile` that meets a character's capsule asks its `HitZones` which part
  is on its line and gets a `HitRecord`; the character's `take_hit()` gives it to its `Health` and its `HitReaction`
  (in `character/`) flinches, throws or pushes the body.
- Components from the synced `addons/gds_game/` that the parts above carry as nodes: `Health` (on every character and
  target: anything with one takes a shot) and `Interactable` (on the door: anything with one is used by the interact
  button). Parts find these by their type, never by a method name.
- `impacts/`: an `Impacts` that makes a mark, an effect and a sound where a `Projectile` lands, by the kind of surface
  (`ImpactSurface` nodes; a body says `surface` in its metadata or a group). Marks are quads on the body that was hit.
- `effects/`: the `EffectEmitter` (one in the level, `world/world.tscn` has it) plays an `EffectDef` (a particles scene,
  a sound, a flash of light, a length) at a point or on a node from a capped pool, so a muzzle flash, an impact or your
  own puff all share one cheap system: `EffectEmitter.find(self).play_at(effect, point, normal)` or `.play_on(effect,
  marker)`. Everything it plays is cosmetic and never sent over the network.
- `net/`: the bytes of an online game (`NetWire`, `CommandCodec`, `SnapshotCodec`) and the limits of one connection
  (`PeerLimits`, `NetLimits`), plain code with no node, socket or clock; `player/player_command.gd` is what one tick
  of a player asks for. The layout of every message is the comment at the top of `net/net_wire.gd`. Under them, the
  link: `NetLink` (send bytes, poll once per physics tick), `WebSocketLink` (the client, desktop and web), `WsListener`
  (the server), `LoopbackLink` (two ends in one process) and `LinkConditioner` (delay, jitter and stalls around any
  link); they carry `PackedByteArray`s and never read them.
- `camera_zone/`: hands the view to another Phantom Camera while the player stands in a trigger zone.
- `door`, `pickup`, `trigger_zone`, `moving_platform`, `spawn_point` and `physics_prop`: map components, each a scene
  with a script and inspector groups, working on its own. Their parts are nodes of the scene (a door's `Panel`,
  `Shape` and `Sensor`), so open the scene to restyle one; the `@tool` scripts size them from the inspector in the
  editor too. Connect their signals in the editor's Node dock (a trigger's `activated` to a door's `open`).
- `pickup/weapon_pickup.tscn`: a `Pickup` that gives a weapon (or its rounds) through the character's loadout, floating
  over a glowing ring; `rifle_pickup.tscn` inherits it with the rifle under `Visual`.
