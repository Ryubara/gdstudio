# Bullet impact sounds

- Source: GDStudio's own work, synthesised by code (`tools/audio/impact_sounds.py` in the kit), nothing sampled and
  nothing third-party. Three seeded variants of each of three surfaces; the seed is the file's name, so the command
  writes the same files again.
- Licence: MIT, Copyright (c) 2026 GDStudio contributors, the licence of the kit. No attribution is required and
  nothing here needs replacing before a commercial release.

| Files | What it is | Seconds |
| --- | --- | ---: |
| `impact_default_1..3.ogg` | a round into stone: a dry smack, a puff of grit and a short low thud | 0.22 |
| `impact_wood_1..3.ogg` | a round into a crate: a hollow knock and a splinter's tick | 0.26 |
| `impact_metal_1..3.ogg` | a round into sheet metal: a click, a ringing ping and a short ricochet whine | 0.45 |

Made with `uv run --with numpy --with scipy python tools/audio/impact_sounds.py --ffmpeg <pinned ffmpeg>`; each file is
peak-normalised to -6 dBFS (the level in the game is the `volume_db` of the surface's `Sound` node).
