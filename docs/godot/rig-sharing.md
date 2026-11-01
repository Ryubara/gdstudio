# Rig sharing (Godot side)

One AnimationLibrary playing on every Quaternius character, in Godot 4.7.2 with the Compatibility renderer. Learned
in the spike `sandbox/rig-sharing/godot/` (kit issue #10) from files cleaned as in
[Rig sharing (Blender)](../blender/rig-sharing.md).

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
- **Raw files.** An uncleaned file imports with its skeleton at `RootNode/CharacterArmature/Skeleton3D`, global scale
  100, and its clips named `CharacterArmature|Walk`: its tracks resolve on no cleaned character.
- **Bone renamed by the importer** when a mesh shares its name (`Body_2`), so that file's clips miss on every other
  character: fixed in Blender.

## Next

- Rest-offset retarget: import each character with a BoneMap onto a custom SkeletonProfile of the 43 shared bones and
  the Rest Fixer (`retarget/rest_fixer/normalize_position_tracks`), or offset position tracks per character
  (`value - source rest + target rest`) when the library is built. Until then share rotation-heavy clips between
  characters of the same build, and keep each body type's own clips for locomotion.

## Evidence

Contact sheet (attached to the pull request): four moments of each clip, both characters playing the same clip from
the same library; rows Walk, Run, Walk_NoPos, Run_NoPos. Reproduce with the commands in
`sandbox/rig-sharing/README.md`.
