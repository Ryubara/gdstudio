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

**`.keep` protects a scratch folder.** The sweep never deletes from `scratch/`, and the [disk guard](#disk) deletes only
the downloads of a scratch topic past its pull request. A folder that holds a file named `.keep` (or sits inside one
that does) is protected from every clean-up anyone writes, and `gds doctor` marks it "protected by .keep" in its list of
big folders. The store and branding assets (Steam, itch.io and
Discord: the app icon and key art) are kept this way: `scratch/deadnight/key-art/.keep` and
`scratch/deadnight/art-key-art/.keep`. Put a `.keep` in any scratch folder that must outlive a clean-up.

## The disk guard {#disk}

On 2026-11-04 the C: drive reached 120 MB free with some 25 agents at work: Godot imports were truncated, a pre-commit
hook emptied a source file, test runs failed. The sweep existed, but nothing watched the disk, and nothing ever deleted
from `scratch/`. Measured then (the workspace was 64 GB of the 923 GB used; the rest was other programs):

| Where | Size | What |
| --- | --- | --- |
| `scratch/` | 50.8 GB | 26 GB of numbered Movie Maker frames (86,000 PNGs), 5 GB of WAV, 6 GB of web exports and CI artifacts |
| `worktrees/` | 7.3 GB | 74 worktrees; 1.2 GB of it `.godot/` import caches |
| `tools/`, `cache/` | 5.2 GB | pinned tools and downloads |
| `%LOCALAPPDATA%\Temp` | 31 GB | 15 GB of Claude Code task output, 1.3 GB of pytest folders |

`gds disk guard` watches the disk and frees what is no longer needed. The kit's hooks start it in the background at
most every five minutes while any session or agent works (a tool call, an agent's start and stop, a session's start
and stop), so it runs on a schedule as long as anyone is working, and its limits are `[disk]` in
`.claude/hooks/hooks.toml`:

| Free space | What happens |
| --- | --- |
| under `soft_gb` (40) | the guard runs the [worktree sweep](#sweep); deletes `.godot/imported` of every worktree nobody has touched for `imports_idle_hours` (2) and no process names (Godot rebuilds it on the next import, as in a fresh worktree); and deletes the downloads of every scratch topic past its pull request (below). Agents are told at start to keep their output small. |
| under `hard_gb` (10) | the same, with the sweep's idle rule at two hours; and **no new task agent and no new worktree starts**: the Agent hook, `gds issue start` and `git worktree add` refuse, with the free space and the biggest folders, until space is back. Helpers and the `reviewer` still start. |

A **scratch topic** is `scratch/<group>/<name>/`. It is past its pull request when the pull requests its `SCRATCH.md`
names (`PR: owner/repo#N` lines) all merged or closed, or, without such a line, when its name is a branch whose pull
requests all merged or closed. Then its downloads go: folders named `artifacts`, `downloads`, `ci-artifacts`, `dl` or
`.godot`; archives (`*.zip`, `*.7z`, `*.tar*`); web exports (`*.pck`, `*.wasm`); raw movie output (`*.avi`); numbered
frames (`*0000.png` and the like); and what the topic's own `Can go: <globs>` line names.

The guard never deletes:

- a worktree the sweep would not remove (a running process, unpublished commits, an open pull request: [the sweep's rules](#sweep));
- the import cache of a worktree touched in the last two hours or named by a running process; anything in `repos/`;
- anything in a scratch topic whose pull request is open or unknown, whose worktree still exists, that a process names,
  that changed in the last `scratch_grace_hours` (2), or that a `.keep` protects;
- a note (`*.md`), or the sweep's `kept/` folders.

**Budgets.** Each worktree has `worktree_budget_gb` (4) and each scratch topic `scratch_budget_gb` (2). The guard
measures them on every run and writes `cache/disk-guard.json`: the free space, the level, what it freed, the folders
over budget and the five biggest. A folder over budget is not deleted for it: it is named, in the status line and in the
refusals, so its owner trims it.

**The status line.** The GDStudio mod `mods/gdstudio-disk/` shows that file's line in Claude Code's status line (`disk
7.7G free HARD<10 | over budget: deadnight/web-night-load 6.1G`) and a toast when the disk falls under the hard limit.
Load it with `claude --plugin-dir <workspace>/repos/gdstudio/mods/gdstudio-disk`, or add that folder to
`CLAUDE_CODE_PLUGIN_DIRS`.

**What agents do.** A downloaded CI artifact is reduced to its numbers (a table in the report or the topic's notes)
and deleted in the same task; raw frames go once the clip or contact sheet is made; a scratch topic's `SCRATCH.md`
names its pull request and what else can go.

```text
gds disk status                 free space, level, and the last run's biggest folders (exit 1 under the hard limit)
gds disk guard                  under the soft limit: free what the rules allow; always: measure, write the status
gds disk guard --dry-run        report what would be freed; delete nothing
gds disk guard --force          free what the rules allow even above the soft limit
```

The report is appended to `scratch/disk-guard.log`. What the guard cannot touch (other programs' folders, `Temp`, the
uv cache) it does not: `gds disk status` and the report name the workspace's folders, and the maintainer decides the rest.

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
