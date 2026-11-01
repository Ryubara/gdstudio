"""Turns RESULT lines from run_bench.sh logs into the markdown tables of docs/godot/crowds.md.

usage: python tabulate_results.py <log> [metric]      metric: mean_ms (default), p95_ms, max_ms, draws
"""

import re
import sys
from collections import defaultdict

ORDER = ["none", "avoid_off", "repath", "tune", "lod", "vis", "bones", "noeyelid", "phys30", "shadows"]


def parse(path: str) -> dict:
    rows: dict = defaultdict(lambda: defaultdict(list))
    for line in open(path, encoding="utf-8"):
        if not line.startswith("RESULT"):
            continue
        kv = dict(p.split("=", 1) for p in line.split()[1:])
        techs = kv["techs"]
        if techs.startswith("all"):
            techs = "all"
        rows[techs][int(kv["count"])].append(kv)
    return rows


def main() -> None:
    path = sys.argv[1]
    metric = sys.argv[2] if len(sys.argv) > 2 else "mean_ms"
    rows = parse(path)
    counts = [10, 20, 40, 80]
    print("| Setup | " + " | ".join(str(c) for c in counts) + " |")
    print("| --- |" + " ---: |" * len(counts))
    base = rows["none"]
    if 0 in base:
        print(f"| empty scene (0 zombies) | {float(base[0][0][metric]):.2f} | | | |")
    for techs in [*ORDER, "all"]:
        if techs not in rows:
            continue
        cells = []
        for c in counts:
            runs = rows[techs].get(c)
            if not runs:
                cells.append("")
                continue
            vals = sorted(float(r[metric]) for r in runs)
            cells.append(f"{vals[len(vals) // 2]:.2f}")
        label = "baseline" if techs == "none" else techs
        print(f"| {label} | " + " | ".join(cells) + " |")


if __name__ == "__main__":
    main()
