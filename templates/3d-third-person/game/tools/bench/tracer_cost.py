"""The hitscan tracer in the web build: its frame cost, its draw call and no program linked at the first streak.

Serves a web export of `tools/bench/tracer_cost.tscn` (`gds template bench-web 3d-third-person tracer_cost` makes it:
kit docs/engines/godot/web-probes.md#bench-web) and reads it as `effects_first_use.py` does (the same page hook, rows
and failures): each run's programs linked, the slowest of its first frames and its mean frame, written to the second
argument; the bench's own rows (draw calls, the script costs) are in its `results`.

    uv run --project <kit>/python gds quiet -- \
        uv run --with playwright==1.64.1 python tools/bench/tracer_cost.py build/web build/tracer_cost.json

Exits 1 when a run after the warm-up linked a program or the bench did not finish. Run it under `gds quiet`. With only
the build folder (as `bench-web --run` calls it) the result goes to `tracer_cost.json` beside that folder.
"""

from __future__ import annotations

import sys
from pathlib import Path

from effects_first_use import main

if __name__ == "__main__":
    if len(sys.argv) == 2:
        sys.argv.append(str(Path(sys.argv[1]).parent / "tracer_cost.json"))
    sys.exit(main())
