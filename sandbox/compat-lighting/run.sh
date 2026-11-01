#!/bin/bash
# Spike runner. Usage: GODOT=<pinned godot> ./run.sh <setup> [out-dir]
# Runs one setup at 1080p (with a screenshot) and 2160p, printing one RESULT line each.
# Bake first with: $GODOT --editor --rendering-method forward_plus --path . -- --bake=low
set -e
: "${GODOT:?set GODOT to the pinned Godot (gds tool path godot)}"
HERE="$(cd "$(dirname "$0")" && pwd)"
OUT="${2:-$HERE/shots}"
mkdir -p "$OUT"
"$GODOT" --path "$HERE" -- --setup="$1" --w=1920 --h=1080 --shot="$OUT/$1.png" 2>&1 | grep -E "RESULT|ERROR|SCRIPT" || true
"$GODOT" --path "$HERE" -- --setup="$1" --w=3840 --h=2160 2>&1 | grep -E "RESULT|ERROR|SCRIPT" || true
