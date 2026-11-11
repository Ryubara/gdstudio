"""Build GDStudio's own animation clips (kit #1154): the review files and the file the game ships.

    uv run --with numpy python -B build_own.py review idle      the three variants of a clip type, for review
    uv run --with numpy python -B build_own.py ship locomotion  a shipped file, from the chosen variants
    uv run --with numpy python -B build_own.py self-test        every check against a clip built to break it

A **review** file (`review/<type>.glb`, with `review/<type>.json` beside it) holds a clip type once per style file
of `styles/` under its letter (`Idle_A`). The game does not import it (`review/.gdignore`); `review_sheet.py` makes
the sheet the maintainer chooses from. A **shipped** file (`<group>.glb` with `<group>.json`) holds each clip of
`GROUPS[group]` once, under its plain name, built with the style `picks.json` names for it; the game imports it as
part of the `gds` animation library.

Every clip passes every check of `gdsanim/checks.py` on every body before anything is written, and the file passes
`../limb_overlap.py` in Blender (`--blender <path>`, the pinned one from `gds tool path blender`; without it the
build says the check was not run and writes nothing unless `--no-overlap` is given). A failed build leaves the
last good file in place and exits 1; the last line of a good build is `BUILT <file>`.

`--check` builds and compares with the files on disk instead of writing: exit 1 when a byte differs.
"""

import argparse
import json
import os
import subprocess
import sys
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
## Blender's Python must not leave `__pycache__` folders in the game (the layout test refuses them).
QUIET = {**os.environ, "PYTHONDONTWRITEBYTECODE": "1"}
sys.path.insert(0, str(HERE))

from clips import idle  # noqa: E402
from gdsanim import build, export, selftest, style  # noqa: E402
from gdsanim.rig import Rig  # noqa: E402
from gdsanim.solve import Solver  # noqa: E402

ASSETS = HERE.parents[1]
## The body clips are solved on, and the bodies every clip is checked on (the reference first).
REFERENCE = ASSETS / "characters/mannequin/mannequin_female.glb"
BODIES = [REFERENCE, ASSETS / "characters/mannequin/mannequin_male.glb"]
## A clip type's description, by its name in lower case.
TYPES = {"idle": ("Idle", idle.describe)}
## The shipped files: the frozen list of clips each carries.
GROUPS = {"locomotion": ["Idle"]}
## The deepest a limb may be inside another part of the body, on every body (mm).
OVERLAP_MM = 5.0


def limb_overlap(blender: str, glb: bytes, bodies: list, report: dict) -> list:
    """Run `../limb_overlap.py` on a file's bytes in Blender; the failures, with the numbers added to `report`."""
    with tempfile.TemporaryDirectory() as folder:
        clips = Path(folder) / "clips.glb"
        numbers = Path(folder) / "overlap.json"
        clips.write_bytes(glb)
        command = [blender, "-b", "--factory-startup", "-P", str(HERE.parent / "limb_overlap.py"), "--"]
        command += ["--clips", clips.as_posix(), "--limit", str(OVERLAP_MM), "--json", numbers.as_posix()]
        for body in bodies:
            command += ["--model", Path(body).as_posix()]
        done = subprocess.run(command, capture_output=True, text=True, timeout=3600, env=QUIET)
        if not numbers.exists():
            return [f"limbs: limb_overlap.py did not finish: {done.stdout[-600:]} {done.stderr[-600:]}"]
        failures = []
        for clip, by_body in json.loads(numbers.read_text(encoding="utf-8")).items():
            name = clip.removesuffix("_Loop")
            for body, entry in by_body.items():
                report.setdefault(name, {}).setdefault("limbs", {})[body] = {
                    "deepest_mm": entry["deepest_mm"],
                    "frame": entry["frame"],
                    "pair": entry["pair"],
                }
                if entry["deepest_mm"] > OVERLAP_MM:
                    failures.append(
                        f"{name}: limbs: {entry['pair']} by {entry['deepest_mm']} mm on {body} at frame {entry['frame']}"
                    )
        return failures


def make(args, builts: list, frozen: list, rig: Rig, bodies: list, out: Path) -> int:
    result = build.build_file(rig, builts, bodies, frozen)
    failures, report = result["failures"], result["report"]
    if args.blender:
        failures += limb_overlap(args.blender, result["glb"], [body.path for body in bodies], report)
    elif not args.no_overlap:
        failures.append("limbs: not checked (give --blender <the pinned Blender>, or --no-overlap to write anyway)")
    if args.report:
        Path(args.report).write_text(json.dumps(report, indent=1, default=str) + "\n", encoding="utf-8", newline="\n")
    for name, numbers in report.items():
        print(f"NUMBERS {name}: {json.dumps(numbers, default=str)}")
    if failures:
        for line in failures:
            print(f"FAILED {line}")
        print(f"NOT BUILT {out.name}: {len(failures)} check(s) failed; the file on disk is the last good one")
        return 1
    side = out.with_suffix(".json")
    text = json.dumps(result["clips"], indent=1, sort_keys=True) + "\n"
    if args.check:
        same = out.exists() and out.read_bytes() == result["glb"] and side.read_text(encoding="utf-8") == text
        print(f"{'SAME' if same else 'DIFFERENT'} {out.name}")
        return 0 if same else 1
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_bytes(result["glb"])
    side.write_text(text, encoding="utf-8", newline="\n")
    print(f"BUILT {out}")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("what", choices=["review", "ship", "self-test"])
    parser.add_argument("name", nargs="?", help="a clip type for review (idle), a group for ship (locomotion)")
    parser.add_argument("--model", type=Path, default=REFERENCE, help="the body clips are solved on")
    parser.add_argument("--body", type=Path, action="append", help="a body to check on (default: both mannequins)")
    parser.add_argument("--blender", help="the pinned Blender, for limbs inside limbs")
    parser.add_argument("--no-overlap", action="store_true", help="write without the limbs check (never to commit)")
    parser.add_argument("--report", help="write the checks' numbers here as json")
    parser.add_argument("--check", action="store_true", help="compare with the files on disk, write nothing")
    args = parser.parse_args()

    rig = Rig(args.model)
    bodies = [rig] + [Rig(path) for path in (args.body or BODIES) if Path(path).resolve() != args.model.resolve()]
    solver = Solver(rig, bodies[1:])
    if args.what == "self-test":
        return selftest.run(rig, solver, bodies)
    styles = {one.letter: one for one in style.load_all(HERE / "styles")}
    if args.what == "review":
        name, describe = TYPES[args.name]
        builts = [build.build_clip(rig, solver, describe(rig, one, f"{name}_{letter}")) for letter, one in styles.items()]
        frozen = [f"{name}_{letter}" for letter in styles]
        return make(args, builts, frozen, rig, bodies, HERE / "review" / f"{args.name}.glb")
    picks = json.loads((HERE / "picks.json").read_text(encoding="utf-8"))["picks"]
    builts = []
    for name in GROUPS[args.name]:
        _, describe = TYPES[name.lower()]
        builts.append(build.build_clip(rig, solver, describe(rig, styles[picks[name]], name)))
    return make(args, builts, GROUPS[args.name], rig, bodies, HERE / f"{args.name}.glb")


if __name__ == "__main__":
    sys.exit(main())
