"""Run every Blender clip build of the template with `--check`, and the limb measure on the files it reports (kit #1481).

Each build makes its files again into a temporary folder and compares them with the committed ones (`clip_check.py`):
a script change that moves a committed clip, or a clip committed without its build, fails here. The kit's CI runs it
with the pinned Blender on Linux (the `blender-clips` job of `.github/workflows/ci.yml`, with `CLIP_CHECK_TOLERANCE`).
Plain Python, no Blender:

    python check_clip_builds.py --blender <the pinned Blender> --hold <aim_seat.json> [--jobs 4] [--logs <folder>]
        [--only <name> ...] [--list]

The prone aim and reload builds read the pistol's hold as the game has it: write `aim_seat.json` first with
`tools/hold/dump_aim_seat.gd` in an imported game made from the template (the template's own folder lacks the addons
`gds new game` adds, and the script stops on the first missing one without quitting). The builds run in parallel;
each passes only when it exits 0 and its last line is `CHECKED <n> same` (Blender exits 0 when a script raises).
`build_own.py` has its own `--check` and is not run here.
"""

import argparse
import os
import subprocess
import sys
import time
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

ANIM = Path(__file__).resolve().parent
GAME = ANIM.parents[1]
MANNEQUIN = GAME / "assets" / "characters" / "mannequin"
PROTOTYPE = GAME / "assets" / "characters" / "prototype"
LOCOMOTION = ANIM / "own" / "locomotion.glb"
HOLD = "{hold}"  # the dumped aim_seat.json, filled in before the run


def prone(body, model, other, out):
    return [
        *(["--body", body] if body else []),
        "--model",
        model,
        "--other",
        other,
        "--library",
        LOCOMOTION,
        "--out",
        out,
    ]


def overlap(clips, models, out):
    return ["--clips", clips, *(a for m in models for a in ("--model", m)), "--brief", "--json", out]


FEMALE, MALE = MANNEQUIN / "mannequin_female.glb", MANNEQUIN / "mannequin_male.glb"
FORM_F, FORM_M = PROTOTYPE / "form_female.glb", PROTOTYPE / "form_male.glb"
P = ANIM / "prone"

# name: (script, arguments after `--`)
BUILDS = {
    "prone": ("prone/build_prone_clips.py", prone("", FEMALE, MALE, P / "prone.glb")),
    "prone_male": ("prone/build_prone_clips.py", prone("male", MALE, FEMALE, P / "prone_male.glb")),
    "prone_form_female": (
        "prone/build_prone_clips.py",
        prone("form_female", FORM_F, FORM_M, P / "prone_form_female.glb"),
    ),
    "prone_form_male": ("prone/build_prone_clips.py", prone("form_male", FORM_M, FORM_F, P / "prone_form_male.glb")),
    "prone_aim": (
        "prone/build_prone_aim_clips.py",
        ["--body", "female", "--model", FORM_F, "--hold", HOLD, "--idle", P / "prone_form_female.glb"]
        + ["--out", P / "prone_aim.glb"],
    ),
    "prone_aim_male": (
        "prone/build_prone_aim_clips.py",
        ["--body", "male", "--model", FORM_M, "--hold", HOLD, "--idle", P / "prone_form_male.glb"]
        + ["--out", P / "prone_aim_male.glb"],
    ),
    "prone_reload": (
        "prone/build_prone_reload_clip.py",
        ["--body", "female", "--model", FORM_F, "--hold", HOLD, "--idle", P / "prone_form_female.glb"]
        + ["--aim", P / "prone_aim.glb", "--out", P / "prone_reload.glb"],
    ),
    "prone_reload_male": (
        "prone/build_prone_reload_clip.py",
        ["--body", "male", "--model", FORM_M, "--hold", HOLD, "--idle", P / "prone_form_male.glb"]
        + ["--aim", P / "prone_aim_male.glb", "--out", P / "prone_reload_male.glb"],
    ),
    "vault": ("vault/build_vault.py", ["--body", "form_female"]),
    "vault_male": ("vault/build_vault.py", ["--body", "form_male"]),
    "vault_quaternius": ("vault/build_vault.py", ["--body", "quaternius_female"]),
    "rifle": (
        "rifle/build_rifle_clips.py",
        ["--out", ANIM / "rifle/rifle_clips.glb", "--data", ANIM / "rifle/rifle_clips.json"],
    ),
    "fixed": ("fixed/build_fixed_clips.py", []),
    "melee": ("melee/build_melee.py", []),
    "pistol_rack": ("pistol/build_pistol_rack.py", ["--out", ANIM / "pistol/pistol_rack.glb"]),
    # The limb measure's reports that no build writes: one a prone file, and the vault's Quaternius pair.
    "overlap_prone": ("limb_overlap.py", overlap(P / "prone.glb", [FEMALE], P / "prone_overlap.json")),
    "overlap_prone_male": ("limb_overlap.py", overlap(P / "prone_male.glb", [MALE], P / "prone_male_overlap.json")),
    "overlap_prone_form_female": (
        "limb_overlap.py",
        overlap(P / "prone_form_female.glb", [FORM_F], P / "prone_form_female_overlap.json"),
    ),
    "overlap_prone_form_male": (
        "limb_overlap.py",
        overlap(P / "prone_form_male.glb", [FORM_M], P / "prone_form_male_overlap.json"),
    ),
    "overlap_vault": (
        "limb_overlap.py",
        overlap(ANIM / "vault/vault_quaternius.glb", [FEMALE, MALE], ANIM / "vault/bodies_overlap.json"),
    ),
}
# Builds that cannot make their committed files today, each with the issue that fixes it: skipped unless named in
# `--only`, and printed, so the gap stays in sight. Take a build off when its issue lands.
KNOWN = {
    "melee": "kit #1493: the build fails its rifle checks since #1399 changed the rifle clips and the torso skin",
}
# Builds whose files only Windows makes again (the committed files were built there): skipped elsewhere unless named in
# `--only`. Blender's floats differ in the last bit between platforms, and this build's search for a pose turns that
# into another pose: on Linux its aim and shot clips come out up to 0.007 apart in a bone's rotation (kit #1481).
WINDOWS_ONLY = {
    "rifle": "its aim clips solve up to 0.007 apart in rotation off Windows (kit #1481)",
}
NEEDS_HOLD = {name for name, (_script, args) in BUILDS.items() if HOLD in args}


def run(blender, name, hold, logs):
    script, args = BUILDS[name]
    args = [hold if a == HOLD else Path(a).as_posix() if isinstance(a, Path) else a for a in args]
    command = [blender, "-b", "--factory-startup", "--python-exit-code", "1"]
    # No __pycache__ beside the builds (the layout check refuses one): Blender ignores PYTHONDONTWRITEBYTECODE.
    command += ["--python-expr", "import sys; sys.dont_write_bytecode = True", "-P", (ANIM / script).as_posix()]
    command += ["--", *args, "--check"]
    env = dict(os.environ, PYTHONDONTWRITEBYTECODE="1")
    start = time.monotonic()
    done = subprocess.run(
        command, check=False, capture_output=True, text=True, encoding="utf-8", errors="replace", env=env
    )
    seconds = time.monotonic() - start
    out = done.stdout + done.stderr
    if logs:
        (Path(logs) / f"{name}.log").write_text(out, encoding="utf-8")
    lines = [
        line for line in done.stdout.splitlines() if line.startswith(("SAME ", "CLOSE ", "DIFFERENT ", "CHECKED "))
    ]
    passed = done.returncode == 0 and bool(lines) and lines[-1].startswith("CHECKED") and lines[-1].endswith(" same")
    if not lines:
        lines = ["no CHECKED line: " + " | ".join(out.strip().splitlines()[-6:])]
    return name, passed, seconds, lines


def main():
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("--blender", help="the pinned Blender (gds tool path blender)")
    parser.add_argument("--hold", help="an aim_seat.json already written by tools/hold/dump_aim_seat.gd")
    parser.add_argument("--jobs", type=int, default=max(1, min(4, os.cpu_count() or 1)))
    parser.add_argument("--logs", help="write each build's output here as <name>.log")
    parser.add_argument("--only", nargs="+", choices=sorted(BUILDS), help="run these builds only")
    parser.add_argument("--list", action="store_true", help="print the builds and exit")
    args = parser.parse_args()
    if args.list:
        for name, (script, _args) in BUILDS.items():
            print(f"{name}: {script}")
        return 0
    if not args.blender:
        parser.error("--blender is required")
    skipped = dict(KNOWN, **({} if sys.platform == "win32" else WINDOWS_ONLY))
    names = args.only or [name for name in BUILDS if name not in skipped]
    for name in sorted(set(skipped) - set(names)):
        print(f"skip {name}: {skipped[name]}", flush=True)
    if NEEDS_HOLD & set(names) and not args.hold:
        parser.error(f"{sorted(NEEDS_HOLD & set(names))} need --hold <aim_seat.json> (tools/hold/dump_aim_seat.gd)")
    if args.logs:
        Path(args.logs).mkdir(parents=True, exist_ok=True)
    hold = Path(args.hold).resolve().as_posix() if args.hold else ""
    failed = []
    with ThreadPoolExecutor(max_workers=args.jobs) as pool:
        for name, passed, seconds, lines in pool.map(lambda n: run(args.blender, n, hold, args.logs), names):
            print(f"{'ok  ' if passed else 'FAIL'} {name} ({seconds:.0f} s): {'; '.join(lines)}", flush=True)
            if not passed:
                failed.append(name)
    print(f"{len(names) - len(failed)} of {len(names)} builds make the committed files again", flush=True)
    if failed:
        print("different or failed: " + ", ".join(failed))
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
