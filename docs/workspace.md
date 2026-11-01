# The workspace

A GDStudio workspace is a plain folder holding every repository and everything that must stay out of them. It is
never a repository itself, so the kit's bootstrap rebuilds it on any machine.

## The layout

| Folder | What lives there |
| --- | --- |
| `repos/` | Checkouts: `gdstudio` (this kit), `gdstudio-assets` (shared asset library), one per game. |
| `worktrees/<repo>/<branch>/` | Every git worktree, so agents work in parallel without sharing a checkout. |
| `scratch/` | Task output, captures, contact sheets, reports, PR text. Never committed. |
| `cache/` | Downloads (`cache/downloads/`) and rebuildable caches shared by all checkouts. |
| `tools/` | Pinned tools from `tools.toml`, as `tools/<name>-<version>/`. |
| `refs/` | Reference images and research downloads: third-party material, never committed. |
| `vault/` | Licensed assets we may use but not redistribute (paid packs). The repos are public: never committed. |

The root also holds `.gdstudio-workspace` (the marker every tool looks for) and `gdstudio.local.toml` (this
machine's tool paths, written by init).

## Bootstrap {#bootstrap}

`bootstrap.ps1` (Windows) and `bootstrap.sh` (Linux, macOS) install uv when missing and run `gds workspace init`,
which:

1. creates the missing folders and the marker;
2. clones the repositories of `workspace.toml` that are missing (`--no-clone` skips it);
3. downloads the pinned tools (`--fetch NAME[,NAME]`, `all` or `none`; the defaults are Godot and Blender), checks
   each against its hash and unpacks it; a mismatch is deleted, never unpacked;
4. writes `gdstudio.local.toml`;
5. checks Git, Git LFS and uv.

Every step is skipped when already done, so it is safe to rerun; `--dry-run` prints the steps.

## Tools {#tools}

`tools.toml` pins each tool's version, per-platform download and hash, copied from the vendor's own checksum file.
Godot runs in self-contained mode (a `_sc_` file beside it), so its settings and export templates stay in its own
`editor_data/` and never mix with another Godot on the machine. Scripts find a tool with `gds tool path <name>`.

Steam or system installs are never used by the tooling: an automatic update would silently change test results.
