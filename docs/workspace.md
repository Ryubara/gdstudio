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

A worktree is temporary: it is removed when its work is finished ([below](#sweep)). Anything worth keeping lives in a
commit or in `scratch/`, never only in a worktree.

## Finished worktrees are swept {#sweep}

Each worktree of a Godot game holds an import cache of tens to hundreds of MB, and removing them by hand after a merge
was skipped under load until the disk was at 8 GB free. `gds worktree sweep` does it for everyone. It also runs in the
background from a [hook](hooks.md#sweep), so nobody has to remember.

A worktree under `worktrees/<repo>/` is **finished** when:

- the pull request of its branch merged (or closed, unless the issue it was made for is still open);
- the issue it was made for (from the issue ledger, remembered after the ledger forgets a closed issue) closed;
- or nothing has touched it for `--idle-hours` (default 6) and no open pull request or started issue claims it: a
  reviewer's, a baseline's or a probe's worktree, detached or on a branch no one opened a pull request for.

A finished worktree is still not removed when:

| Rule | Why |
| --- | --- |
| it was touched in the last `--grace-minutes` (30) | the agent that owns it may be between two commands; "touched" is git's own files, the changed files and the folders two levels down (a Godot editor writes `.godot/`) |
| a running process names it in its command line or has it as its working directory | on Windows only the command line is known, which is why the grace exists |
| it has commits on no remote branch and not in the merged pull request | unpublished work |
| it has an open pull request, an open started issue, a lock, or `main` checked out | still in use |
| the files to keep are over `--max-keep-mb` (1024) | copy them by hand, then run the sweep again |
| GitHub cannot be asked (a branch worktree) | the pull request state is unknown |

**What is kept.** Before a worktree is removed, every changed or untracked file of it that is not generated is copied,
with its folder layout, to `scratch/<repo>/<branch>/kept/` (`kept-2/` if an earlier sweep used the name), with
`kept.md` listing them and `tracked.patch` (`git diff HEAD`) for the changes to tracked files. That covers artwork
(`.blend`, renders, `.glb`, textures), notes (`REVIEW.md`, `STATUS.md`) and probes. Generated files are not kept:
`.godot/`, `*.uid`, `*.import`, `__pycache__/`, caches, GdUnit `report_*/` folders, and export output (`export/`,
`build/`, `*.pck`, `*.exe`, `*.wasm`). Files that git ignores are not copied; the local branch is deleted with the
worktree, because its commits are on the remote or in the merged pull request.

```text
gds worktree sweep                    remove what is finished and report it
gds worktree sweep --dry-run          report only; copies, removes and deletes nothing
gds worktree sweep --only NAME ...    only these worktree folders (--repo limits to repositories)
gds worktree sweep --no-idle          pull request and issue rules only
```

The report lists, per worktree, `removed` / `would remove` (with its size and the files kept), `refused` (finished, but
a rule above stopped it) and `left` (not finished), then a summary with the space freed. The background run appends it to
`scratch/worktree-sweep.log`.

`gds doctor` warns when the workspace's disk has under 20 GB free and names the biggest worktrees and scratch folders.

**Scratch folders are never swept, and `.keep` protects them.** Nothing in the kit deletes from `scratch/`. A folder that
holds a file named `.keep` (or sits inside one that does) is protected from every clean-up anyone writes, and `gds
doctor` marks it "protected by .keep" in its list of big folders. The store and branding assets (Steam, itch.io and
Discord: the app icon and key art) are kept this way: `scratch/deadnight/key-art/.keep` and
`scratch/deadnight/art-key-art/.keep`. Put a `.keep` in any scratch folder that must outlive a clean-up.

## Bootstrap {#bootstrap}

`bootstrap.ps1` (Windows) and `bootstrap.sh` (Linux, macOS) install uv when missing and run `gds workspace init`,
which:

1. creates the missing folders and the marker;
2. clones the repositories of `workspace.toml` that are missing (`--no-clone` skips it);
3. downloads the pinned tools (`--fetch NAME[,NAME]`, `all` or `none`; the defaults are Godot and Blender), checks
   each against its hash and unpacks it; a mismatch is deleted, never unpacked;
4. writes `gdstudio.local.toml`;
5. sets up the [integrations](#integrations);
6. checks Git, Git LFS and uv.

Every step is skipped when already done, so it is safe to rerun; `--dry-run` prints the steps.

## Tools {#tools}

`tools.toml` pins each tool's version, per-platform download and hash, copied from the vendor's own checksum file.
Godot runs in self-contained mode (a `_sc_` file beside it), so its settings and export templates stay in its own
`editor_data/` and never mix with another Godot on the machine. Scripts find a tool with `gds tool path <name>`.

Steam or system installs are never used by the tooling: an automatic update would silently change test results.

## Integrations {#integrations}

| What | Where | How |
| --- | --- | --- |
| ffmpeg | `tools/ffmpeg-<version>/` | pinned like Godot; clips from captures (Windows build pinned; elsewhere the system package) |
| Blender in portable mode | `tools/blender-<version>/.../portable/` | its settings and add-ons stay apart from any other Blender |
| Blender MCP add-on | inside the pinned Blender | installed as an extension |
| Godot MCP addon | each game's `game/addons/godot_mcp/` | copied in, enabled by an untracked `game/override.cfg`, excluded in `.git/info/exclude`: third-party code stays out of the public repositories |
| MCP servers (`godot`, `blender`) | Claude Code, per checkout | `claude mcp add -s local`, from `[mcp]` in `tools.toml`; skipped when registered or with `--no-mcp` |

The Godot MCP drives a live editor and the Blender MCP a live Blender: open the pinned program with its add-on enabled
before an agent uses them. Headless scripts and Movie Maker need neither.
