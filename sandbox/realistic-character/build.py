"""Builds the realistic character experiment from nothing but Blender Studio's CC0 base mesh.

    python build.py --blender "$(gds tool path blender)" --work <scratch folder> \\
        --base <human_base_meshes_bundle.blend> --mannequin <mannequin_female.glb> [--quick] [--from s05]

Each stage is one headless Blender run that opens the .blend the stage before it saved in the work folder; a stage
that fails stops the build (`--python-exit-code 1`: without it Blender exits 0 on a Python error). `--quick` bakes
the texture sets at a quarter of their size. The asset is never written into the repository: `--work` and `--out`
are folders outside it. Kit docs: docs/tools/blender/realistic-characters.md.
"""

import argparse
import subprocess
import sys
import time
from pathlib import Path

HERE = Path(__file__).resolve().parent / "blender"
STAGES = ["s01_sculpt", "s02_skin", "s03_eyes", "s04_hair", "s05_outfit", "s06_outfit_tex", "s07_rig", "s08_export"]


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--blender", required=True)
    p.add_argument("--work", required=True)
    p.add_argument("--base", required=True, help="human_base_meshes_bundle.blend (Blender Studio, CC0)")
    p.add_argument("--mannequin", required=True, help="the template's mannequin_female.glb: the library rig's rest")
    p.add_argument("--out", default="", help="where stage 8 writes the glb and the textures for Godot")
    p.add_argument("--quick", action="store_true")
    p.add_argument("--from", dest="start", default=STAGES[0][:3])
    a = p.parse_args()
    work = Path(a.work).resolve()
    work.mkdir(parents=True, exist_ok=True)
    out = Path(a.out).resolve() if a.out else work / "export"
    start = next(i for i, s in enumerate(STAGES) if s.startswith(a.start))
    for stage in STAGES[start:]:
        base = a.mannequin if stage == "s07_rig" else a.base
        cmd = [a.blender, "-b", "--python-exit-code", "1", "-P", str(HERE / f"{stage}.py"), "--",
               "--work", work.as_posix(), "--base", Path(base).resolve().as_posix(), "--out", out.as_posix()]
        if a.quick:
            cmd.append("--quick")
        t = time.time()
        run = subprocess.run(cmd, capture_output=True, text=True, timeout=3600)
        (work / f"{stage}.log").write_text(run.stdout + run.stderr, encoding="utf-8")
        for line in run.stdout.splitlines():
            if line.split(" ")[0].isupper() and len(line.split(" ")[0]) > 2:
                print(" ", line)
        print(f"{stage}: exit {run.returncode}, {time.time() - t:.0f} s")
        if run.returncode:
            print(run.stderr[-3000:])
            sys.exit(1)
    print("BUILT")


main()
