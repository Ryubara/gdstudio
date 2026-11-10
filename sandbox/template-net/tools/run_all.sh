#!/bin/sh
# The matrix of the findings page: every mode at 2, 8 and 16 players (all walking), and 16 with 4 walking.
# usage: tools/run_all.sh <godot> > results.txt
GODOT="$1"
port=8970
for players in 2 8 16; do
  for mode in sync sync_packed rpc_bytes send_bytes send_delta; do
    port=$((port + 2))
    uv run --project ../../python --with psutil python tools/run.py --godot "$GODOT" --mode $mode --players $players --moving $players --seconds 8 --port $port
  done
done
for mode in sync sync_packed rpc_bytes send_bytes send_delta; do
  port=$((port + 2))
  uv run --project ../../python --with psutil python tools/run.py --godot "$GODOT" --mode $mode --players 16 --moving 4 --seconds 8 --port $port
done
