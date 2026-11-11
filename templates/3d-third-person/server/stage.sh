#!/usr/bin/env bash
# Makes the game server's build context: the Dockerfile, railway.toml and the Godot project at game/, without what
# the server never loads (the import cache, the test suites and their reports, the tools, GdUnit4 and the editor's
# MCP addon; the same folders the web export leaves out).
#
#   server/stage.sh <folder>        the folder is emptied first; then: docker build -t game-server <folder>
set -euo pipefail

stage=${1:?usage: server/stage.sh <folder>}
here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/.." && pwd)
[ -f "$root/game/project.godot" ] || { echo "no Godot project at $root/game" >&2; exit 1; }

rm -rf "$stage"
mkdir -p "$stage"
cp "$here/Dockerfile" "$here/railway.toml" "$stage/"
tar -C "$root" \
    --exclude='game/.godot' --exclude='game/reports' --exclude='game/tests' --exclude='game/tools' \
    --exclude='game/addons/gdUnit4' --exclude='game/addons/godot_mcp' \
    -cf - game | tar -C "$stage" -xf -
echo "staged $(git -C "$root" rev-parse --short HEAD 2>/dev/null || echo 'a tree') in $stage"
