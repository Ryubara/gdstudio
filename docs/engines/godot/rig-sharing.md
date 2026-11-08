# Rig sharing (Godot side)

One AnimationLibrary playing on every Quaternius character, in Godot 4.7.2 with the Compatibility renderer. Learned
in the spike `sandbox/rig-sharing/godot/` (kit issue #10) from files cleaned as in
[Rig sharing (Blender)](../../tools/blender/rig-sharing.md).

## The recipe

Plain matching names are enough: every cleaned file imports to `CharacterArmature/Skeleton3D` with the same bone
names, so a track `CharacterArmature/Skeleton3D:UpperLeg.L` resolves on every character. No BoneMap or
SkeletonProfile is needed within the Quaternius rig (they would be for a rig with other names, e.g. a Mixamo one).

```gdscript
var lib := AnimationLibrary.new()
lib.add_animation("Walk", zombie_player.get_animation("Walk").duplicate(true))
lib.add_animation("Run", soldier_player.get_animation("Run").duplicate(true))
for player in [soldier_player, zombie_player]:
    player.add_animation_library("rig", lib)   # 4.7: add_animation_library, not add_library
soldier_player.play("rig/Walk")
```

The library can be saved with `ResourceSaver.save(lib, "....tres")` and loaded by any character.

## Measured

| | Walk (from the zombie) | Run (from the Soldier) |
| --- | --- | --- |
| Length | 1.333 s | 0.708 s |
| Tracks after import | 56 (47 rotation, 9 position) | 34 (27 rotation, 7 position) |
| Tracks naming a bone the other character lacks | 5 on the Soldier: Eyelid.L/R, Tongue3-5 | 0 |
| Root motion | none (no `Root` position track) | none |
| `Body` position range | 0.098 m up and down | 0.207 m |

The cleaned Walk is exported sampled, 150 channels (every bone); Godot's importer drops the ones that never change and
keeps 56, so a clip carries only the bones it moves.

## What breaks

- **Extra bones: nothing.** The zombie's Walk on the Soldier names five bones he does not have; they are skipped with
  no error. The Soldier's clips leave the zombie's tongue and eyelids at rest.
- **Rest offsets: position tracks are absolute.** `Body` rests at z = -0.828 in the Soldier and -0.510 in the zombie
  (0.32 m apart, bone space), and the leg bones carry position keys too. A clip moves the bone to the *source*
  character's position: the zombie's Walk sinks the Soldier's feet through the floor; the Soldier's Run lifts the
  zombie off it. Stripping every position track (`Walk_NoPos`, `Run_NoPos` on the sheet) fixes the height at rest but
  loses the bob, and the bent legs then push the feet below the floor at the bottom of each step.
  **Fix that works: rebase the position keys per character** (`Walk_Rebased`, `Run_Rebased` on the sheet, feet on
  the floor for both): see below.
- **Raw files.** An uncleaned file imports with its skeleton at `RootNode/CharacterArmature/Skeleton3D`, global scale
  100, and its clips named `CharacterArmature|Walk`: its tracks resolve on no cleaned character.
- **Bone renamed by the importer** when a mesh shares its name (`Body_2`), so that file's clips miss on every other
  character: fixed in Blender.

## Rebasing position keys (one library, every body)

When a clip goes into the library, store the source skeleton's rest position of every bone it moves as clip
metadata; each character's AnimationPlayer runs `sandbox/rig-sharing/godot/retarget_player.gd`, which overrides
`AnimationMixer._post_process_key_value` and returns `value - source rest + own rest` for position keys. The library
stays one resource; the offset is applied per character at play time.

```gdscript
func _post_process_key_value(animation, track, value, object_id, object_sub_idx):
    if animation.track_get_type(track) != Animation.TYPE_POSITION_3D or not animation.has_meta("src_rest"):
        return value
    var sk := instance_from_id(object_id) as Skeleton3D
    var bone := sk.get_bone_name(object_sub_idx)
    return value - animation.get_meta("src_rest").get(bone, sk.get_bone_rest(object_sub_idx).origin)         + sk.get_bone_rest(object_sub_idx).origin
```

It runs GDScript for every position key on every character each frame (9 tracks for Walk); measure it in the crowds
spike before 40 zombies use it. Baking one rebased copy of each clip per body type when the library is built costs
memory instead of frame time.

## Next

- Cost of the rebasing callback with a crowd (the crowds spike), against baked per-body copies.
- BoneMap and a SkeletonProfile only when a rig with other bone names joins (Mixamo, other packs).

## Evidence

Contact sheet (attached to the pull request): four moments of each clip, both characters playing the same clip from
the same library; rows Walk, Run, Walk_NoPos, Run_NoPos. Reproduce with the commands in
`sandbox/rig-sharing/README.md`.

## Found later {#found-later}

From the Soldier's weapon clips (Deadnight #42):

- The skeleton rest in Godot is still Blender's rest (arms out): something must always play.
- `remove_immutable_tracks` keeps a constant track whose value differs from the rest, so baked static-pose tracks
  survive.
- An AnimationTree built in a SceneTree script's `_init` does not process; build it from a deferred call.

From the fence boards' clips (Deadnight #221):

- New clips for a shared rig can live in a file of their own (the rig, a mesh so Godot builds a `Skeleton3D`, and only
  the new clips) and be added to the shared `AnimationLibrary` at load: the bodies' files are not rebuilt.
- An `AnimationNodeTimeSeek` request is taken on the tree's next `advance`, and that advance moves no further: with a
  manually advanced tree (a crowd throttle advancing far zombies every Nth frame) the whole saved-up delta is lost.
  Call `advance(0.0)` right after setting the request, then play the saved time.
- To put a clip's event on a moment the rules decide (a board torn every `P` seconds), seek to the event frame on the
  rules' event and scale the clip to one loop per `P`; for the first one, start at frame 0 scaled so the event frame
  lands `P` later.

From the grenade throw (Deadnight #377):

- To hold a clip's last frame while a button is down (a cooked grenade), play it through an `AnimationNodeAnimation`
  with `use_custom_timeline = true` and `stretch_time_scale = false`: the node stops on the last frame instead of
  looping or ending the one-shot.

From the Soldier's aim-move clips (Deadnight #74):

- **Stepping a tree by hand reads stale global poses.** `Skeleton3D.get_bone_global_pose()` is refreshed on the
  skeleton's deferred update, which a test that calls `AnimationTree.advance()` in a loop never reaches; read
  `get_bone_pose_position/rotation` and compose with the parent's global pose (a bone under a still `Root`, such as
  the kit's `Foot` bones, needs nothing else). Deadnight #74.
- **A state machine without an automatic first transition stays at `Start`.** Deadnight's player body enters
  locomotion on its first landing; a test with physics off calls `playback.start()` itself.

- **Approach:** When a view swaps a character's model (a look or a colour changed), add the new model hidden, keep the
  old one on screen, and swap them on the next `process_frame`. **Watch out for:** a model instanced from a `.glb` stays
  in its rest pose (arms out) until its `AnimationPlayer` and skeleton have run once, and `play()` with `advance(0.0)`
  before the first process does not pose it in time, so captures caught a T-pose for a frame on every rebuild. **Seen:**
  Deadnight, 2026-11-01 (fix: the preview swaps on the next frame).

## Skeleton modifiers

A `SkeletonModifier3D` (for example arm IK that puts both hands on a held weapon) changes the pose only for the
skeleton's update: read and test its result in a `skeleton_updated` handler, since `get_bone_global_pose` after the
frame returns the clip's pose. Blend the modifier out while a clip owns the arms (reload, swing). Held items are
scaled by one written rule against the character's in-game height, including any scale on the character's scene.
