#!/usr/bin/env bash
# Runs the whole benchmark matrix with the pinned Godot and appends RESULT lines to a log.
# usage: run_bench.sh <godot.exe> <log> [--headless]
set -u
GODOT="$1"; LOG="$2"; MODE="${3:-}"
cd "$(dirname "$0")"
: > "$LOG"
run() {
  "$GODOT" $MODE --path . --fixed-fps 60 -- --count="$1" --techs="$2" --warmup=300 --frames=400 2>&1 | grep -E "RESULT|ERROR" >> "$LOG"
}
run 0 ""
for count in 10 20 40 80; do
  for techs in "" avoid_off repath tune lod vis bones noeyelid phys30 all; do
    run "$count" "$techs"
  done
done
# Cost of a dynamic shadow, and run-to-run noise on a busy machine
run 40 shadows
run 40 ""
run 40 ""
