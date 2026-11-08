# Pistol

The template's weapon model: Deadnight's service pistol (a generic 1911 type), GDStudio's own script-built model, at
real length with the Toon Shooter kit's chunky cross-sections. Licence: [LICENSE.md](LICENSE.md).

| File | What it is |
| --- | --- |
| `pistol.glb` | The model: 692 triangles, one material (`Weapons`) on the palette, 0.250 x 0.196 x 0.049 m |
| `pistol_weapons_palette.png` | The 32 x 32 palette Godot extracts from the glb (lossless, no mipmaps, Detect 3D off) |
| `pistol_held.tscn` | A `BoneAttachment3D` on `hand_r` with the pistol seated in the right fist |
| `build_pistol.py` | Rebuilds `pistol.glb` with the pinned Blender (`blender -b --factory-startup -P build_pistol.py`) |

## Nodes

The glb's root is `Pistol` (the frame and grip), origin at the grip. In Godot the muzzle points along -X, up is +Y and
the gun's left is +Z (the kit's weapon axes).

| Node | Where (m, in `Pistol`) | Use |
| --- | --- | --- |
| `Slide` | (0.008, 0.111, 0) | the slide, origin at its rear: move it along +X for the shot (Deadnight uses 0.05 m) |
| `Magazine` | (0.003, -0.042, 0) | the magazine, origin at its foot: drop it along the grip for a reload |
| `Muzzle` | (-0.202, 0.103, 0) | the barrel's open end; its -Z points out of the barrel (flash, shot) |
| `Eject` | (-0.092, 0.123, -0.020) | the ejection port on the right; its -Z points out of the port |
| `Grip` | (0, 0, 0) | the right hand's handle; +Y up the handle, -Z along the fingers (the barrel) |
| `Trigger` | (-0.062, 0.046, 0) | the trigger's front face; -Z is the press |

## Holding it

Instance `pistol_held.tscn` as a child of the mannequin's `Skeleton3D` (`Player/Model/Armature/Skeleton3D`): the
`BoneAttachment3D` follows `hand_r` and seats the pistol in the fist of every Universal Animation Library pistol clip
(`ual1/Pistol_Idle`, `Pistol_Aim_Neutral`, `Pistol_Aim_Up`, `Pistol_Aim_Down`, `Pistol_Shoot`, `Pistol_Reload`). The
pistol's place in the `hand_r` bone's space is:

```text
Transform3D(0.0234, -0.0805, -0.9965, -0.9867, 0.1585, -0.036, 0.1609, 0.9841, -0.0757, -0.0264, 0.1234, 0.0091)
```

The grip sits 12.3 cm along the bone (+Y, wrist to knuckles) and 2.6 cm to its -X, the barrel runs along the bone's +Y
tilted 9 degrees toward its -Z, and the pistol's up is the bone's +Z. Measured against the skinned hand as Godot plays
`Pistol_Aim_Neutral`: the barrel points 1.5 degrees up and 3 degrees out from the character's facing, the index finger
lies along the frame to the trigger, three fingers close on the grip, and the knuckles sink at most 9.5 mm into the
grip panels (none of it shows from the camera). The fist is the same in all six clips, so one hold fits them all.

The model is drawn at real length because the mannequin is real-sized (1.8 m); its chunky cross-sections fill the
clips' fist and read from the third-person camera (the slide is about 9 pixels tall at 1080p from 4.4 m). How the size
and the hold were chosen is in the kit's `docs/tools/blender/weapons.md#the-third-person-template-pistol`.
