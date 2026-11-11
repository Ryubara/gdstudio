#!/bin/sh
# A local git filter that `gds workspace init` writes into a checkout's git folder (docs/studio/workspace.md#integrations);
# never committed, never run by hand. Godot 4.7's editor reads its plugin list only from project.godot (it ignores
# override.cfg), so the local-only addons are listed there, and this filter keeps them out of git:
#   clean  <path> <addon>...  drops each addon from the `enabled=PackedStringArray(...)` line: commits, diffs and
#                             status never see it;
#   smudge <path> <addon>...  adds each one back whose folder is installed beside that project.godot (a fresh
#                             worktree has none, and Godot reports a listed plugin it cannot find).
# Git runs it from the top of the working tree, with the file on stdin and the result on stdout.
mode=$1
dir=$(dirname "$2")
shift 2
script=""
for addon in "$@"; do
	entry="\"res://addons/$addon/plugin.cfg\""
	if [ "$mode" = clean ]; then
		script="$script
/^enabled=PackedStringArray(/s|, $entry||g"
	elif [ -f "$dir/addons/$addon/plugin.cfg" ]; then
		script="$script
\\|$entry|!s|^\\(enabled=PackedStringArray(.*\"\\))|\\1, $entry)|"
	fi
done
exec sed "$script"
