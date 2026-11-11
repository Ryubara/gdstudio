#!/usr/bin/env bash
# Checks a running game server from this checkout's game: bots play against it (tools/net/server_bot.gd), every one
# must be welcomed and still connected at the end, then one bot says hello with an older protocol version and must be
# refused for it. Prints the bots' SERVER_BOT lines (slots, round trips, connect time, bytes each way).
#
#   GODOT=<pinned godot> server/check.sh <url> [bots] [seconds] [more bot options, e.g. --moves]
#   server/check.sh ws://127.0.0.1:8910 8 60              the image run locally
#   server/check.sh wss://<service>.up.railway.app 8 600  a deployment (TLS ends at Railway's edge)
#
# GODOT is the kit's pinned Godot (`gds tool path godot`); without it, `godot` from PATH.
set -euo pipefail

url=${1:?usage: server/check.sh <url> [bots] [seconds] [bot options]}
bots=${2:-8}
seconds=${3:-60}
shift $(($# < 3 ? $# : 3))
here=$(cd "$(dirname "$0")" && pwd)
game="$here/../game"
# Git Bash: a Windows Godot needs a Windows path, which MSYS_NO_PATHCONV=1 would keep it from getting.
if command -v cygpath >/dev/null 2>&1; then game=$(cygpath -m "$game"); fi
godot=${GODOT:-godot}
bot=(--headless --path "$game" -s res://tools/net/server_bot.gd --)

echo "== $bots bot(s) for $seconds s against $url"
if ! timeout $((seconds + 120)) "$godot" "${bot[@]}" --connect "$url" --bots "$bots" --seconds "$seconds" "$@"; then
    echo "FAILED: a bot was not welcomed or lost its connection (a kick); read the server's log for kicked lines" >&2
    exit 1
fi
echo "== an older client's hello"
if ! timeout 120 "$godot" "${bot[@]}" --connect "$url" --bots 1 --seconds 3 --version old; then
    echo "FAILED: the server did not refuse a hello of an older protocol version" >&2
    exit 1
fi
echo "PASSED: $bots bot(s) played $seconds s and an older client was refused"
