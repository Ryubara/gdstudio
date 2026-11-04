---
areas: [tools, tests, general]
---
# An import on a full disk left truncated files that Godot read as corrupt

2026-11-04

- **Saw:** a windowed run in a fresh worktree printed `Compressed texture file is corrupt (Bad header)`, then
  `Failed loading resource` for a mesh and a glTF, then a null night (`Nonexistent function 'words' in base 'Nil'`).
  `--import` itself printed nothing wrong and exited 0, and a `--quit-after 30` smoke run was clean (it loads none of
  these). `.godot/imported` held files of 0 bytes, 4 096 bytes and 4 bytes, and the tracked `*.import` files had been
  rewritten with `valid=false` (a dirty tree of 150 files after an import).
- **Cause:** drive C: was full (5 GB free at the start, 120 MB later: another agent's downloaded CI artifacts under
  `scratch/` grew 6 GB while the import ran). Godot writes what it can and goes on; a failed importer saves
  `valid=false` into the tracked `.import` file, and a later `--import` trusts it.
- **Fix:** look at free space before a first import and at the start of a measuring session (`df -k /c`, or
  `Get-PSDrive C`); after a full-disk import, `git checkout -- '*.import'`, delete `.godot/imported` and
  `.godot/editor/filesystem_cache*`, import again once there is room, and check
  `find .godot/imported -type f -size -5c` is empty and `git status` shows no `.import` file changed. Never delete
  another agent's scratch folder to make room: report it.
- **Docs:** [Performance review](../godot/performance-review.md#how-to-measure-it-counts-first) (check the disk
  before a measuring session).
