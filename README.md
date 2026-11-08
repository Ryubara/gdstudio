# GDStudio kit

Shared tooling, agent rules, asset pipelines and global docs for GDStudio's Godot games.

## Set up a workspace

Needs Git (with Git LFS). The bootstrap installs [uv](https://docs.astral.sh/uv/) if missing, builds the workspace
folders, clones the repositories and downloads the pinned Godot and Blender, checking every download's hash.

```sh
# Windows (PowerShell), from an empty folder that becomes the workspace:
irm https://raw.githubusercontent.com/Ryubara/gdstudio/main/bootstrap.ps1 -OutFile bootstrap.ps1
powershell -ExecutionPolicy Bypass -File bootstrap.ps1

# Linux / macOS:
curl -LsSfO https://raw.githubusercontent.com/Ryubara/gdstudio/main/bootstrap.sh && sh bootstrap.sh
```

From an existing clone at `<workspace>/repos/gdstudio`, run `./bootstrap.sh` or `bootstrap.ps1` there. Add
`--fetch all` for the Godot export templates too, `--dry-run` to see the steps first. Details: `docs/studio/workspace.md`.

The [docs hub](https://ryubara.github.io/gdstudio/) has the workspace guide and everything the games share.
