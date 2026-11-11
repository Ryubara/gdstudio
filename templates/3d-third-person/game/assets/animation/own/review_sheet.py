"""Make a clip type's review sheet (kit #1154, `docs/tools/blender/own-animation.md#review`). No hand step:

    uv run --with numpy --with pillow python -B review_sheet.py idle --blender <the pinned Blender> --out <folder>
        [--report <the build's --report json>] [--frames 5] [--speed <m/s the floor moves at>]

It reads the review file `review/<type>.glb` with its `review/<type>.json`, and the library clip the type replaces
(the `replaces` of its clips, `ual1/Idle`), and writes into `--out`:

- `<type>_sheet.png`: the **strip** (a column per variant and a last one for the library clip, each the same
  frames of the cycle, in rows from the side, the front and the top, over a floor of 0.25 m squares that moves at
  the clip's speed), the **other bodies** (one frame of each variant on every body), the **numbers** with their
  limits and the **notes** of each style file;
- `<type>_numbers.md`: the numbers as a table for the pull request.

The numbers are `../audit_clips.py`'s, the measures the library's clips were audited with, so a variant and the
clip it replaces are read on one scale; `--report` adds the build's own (support, limbs inside limbs, reduction).
The clip from the game's camera is the other half of a review: `tools/capture/own_clips_review.tscn`.
"""

import argparse
import json
import os
import subprocess
import sys
import tempfile
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFont

HERE = Path(__file__).resolve().parent
## Blender's Python must not leave `__pycache__` folders in the game (the layout test refuses them).
QUIET = {**os.environ, "PYTHONDONTWRITEBYTECODE": "1"}
sys.path.insert(0, str(HERE))

from gdsanim import checks, export, style  # noqa: E402
from gdsanim.rig import Rig, audit_clips  # noqa: E402

ASSETS = HERE.parents[1]
BODIES = [ASSETS / "characters/mannequin/mannequin_female.glb", ASSETS / "characters/mannequin/mannequin_male.glb"]
LIBRARIES = {"ual1": ASSETS / "animation/universal/ual1.glb", "ual2": ASSETS / "animation/universal/ual2.glb"}
VIEWS = ("side", "front", "top")
CELL, TOP_CELL = (230, 330), (230, 230)
INK, PAPER, FAINT, BAD = (232, 234, 238), (30, 33, 38), (150, 155, 165), (255, 140, 120)
## The rows of the numbers table: the audit's key, what it is, and its limit in words (empty: no limit, a
## number to compare).
ROWS = [
    ("seconds", "length (s)", ""),
    ("moving_bones", "bones that move", "the library's idle moves 17"),
    ("finger_bones", "of them fingers", "over 0: no dead hands"),
    ("pelvis_sway_mm", "pelvis side to side (mm)", ""),
    ("pelvis_bob_mm", "pelvis up and down (mm)", ""),
    ("pelvis_travel_mm", "pelvis fore and aft (mm)", ""),
    ("pelvis_roll", "hips tip (degrees)", ""),
    ("pelvis_yaw", "hips turn (degrees)", ""),
    ("chest_yaw", "shoulders turn (degrees)", ""),
    ("head_yaw", "head turns (degrees)", ""),
    ("speed", "planted sole speed (m/s)", "the game's speed, within 2 %"),
    ("cadence", "steps a minute", ""),
    ("duty", "planted share", ""),
    ("slide_mm", "planted sole wanders (mm)", f"at most {checks.WANDER * 1000:.0f}"),
    ("floor_mm", "lowest sole vertex (mm)", f"no more than {checks.UNDER * 1000:.0f} under"),
    ("seam_mm", "seam open (mm)", "0"),
    ("seam_step", "seam's change of speed", f"at most {checks.SEAM_STEP:.0f}"),
    ("keys_kept", "keys a reducer keeps", f"at most {checks.KEYS_KEPT:.0%}"),
    ("kb", "clip's bytes in its file (KB)", ""),
]
## The rows that say nothing of a clip that stands.
GAIT_ROWS = ("speed", "cadence", "duty")
REPORT_ROWS = [
    (("weight", "support_margin_mm"), "centre of mass inside the feet (mm)", "over 0"),
    (("cost", "kb_a_second"), "key bytes a second (KB)", f"at most {checks.KB_A_SECOND:.0f}"),
    (("reduce_error_mm",), "reduced keys off the full curve (mm)", "at most 1"),
]


def library_clip(rig: Rig, replaces: str, name: str) -> dict | None:
    """A library clip (`ual1/Idle`) on a body, as a clip the exporter writes, under `name`."""
    if "/" not in replaces:
        return None
    library, clip = replaces.split("/")
    glb = audit_clips.Glb(LIBRARIES[library])
    anim = next(a for a in glb.json["animations"] if a["name"].removesuffix("_Loop") == clip)
    rotation, translation = audit_clips.sample(glb, anim, rig.body)
    every = np.arange(rotation.shape[0])
    bones = [n for n in rig.bones if n != rig.parent["pelvis"]]
    return {
        "name": name,
        "loop": anim["name"].endswith("_Loop"),
        "rotation": rotation,
        "translation": translation,
        "kept": {"rotation": {n: every for n in bones}, "place": {"pelvis": every}},
    }


def review_clips(rig: Rig, path: Path) -> list:
    """The clips of a review file on a body (the same keys, on the body's own bones)."""
    out = []
    for name, tracks in export.read_keys(path).items():
        count = int(round(max(times[-1] for times, _ in tracks.values()) * 30)) + 1
        rotation = np.repeat(rig.body.rest_r[None], count, axis=0)
        translation = np.repeat(rig.body.rest_t[None], count, axis=0)
        kept = {"rotation": {}, "place": {}}
        for (bone, kind), (times, values) in tracks.items():
            if bone not in rig.index:
                continue
            frames = np.rint(times * 30).astype(int)
            if kind == "rotation":
                rotation[frames, rig.index[bone]] = values
                kept["rotation"][bone] = frames
            else:
                translation[frames, rig.index[bone]] = values * rig.motion_scale
                kept["place"][bone] = frames
        out.append(
            {
                "name": name.removesuffix("_Loop"),
                "loop": name.endswith("_Loop"),
                "rotation": rotation,
                "translation": translation,
                "kept": kept,
            }
        )
    return out


def text(draw: ImageDraw.ImageDraw, at: tuple, words: str, size: int = 16, fill: tuple = INK) -> None:
    draw.text(at, words, font=ImageFont.load_default(size=size), fill=fill)


def fmt(value) -> str:
    if value is None:
        return "-"
    if isinstance(value, bool):
        return "yes" if value else "no"
    if isinstance(value, float):
        return f"{value:.2f}".rstrip("0").rstrip(".")
    return str(value)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("type")
    parser.add_argument("--blender", required=True)
    parser.add_argument("--out", type=Path, required=True)
    parser.add_argument("--report", type=Path)
    parser.add_argument("--frames", type=int, default=5)
    parser.add_argument("--speed", type=float, help="metres a second the floor moves at (default: the clip's own)")
    parser.add_argument("--body", type=Path, action="append")
    args = parser.parse_args()

    review = HERE / "review" / f"{args.type}.glb"
    records = json.loads(review.with_suffix(".json").read_text(encoding="utf-8"))["clips"]
    styles = {one.letter: one for one in style.load_all(HERE / "styles")}
    names = list(records)
    replaces = records[names[0]]["replaces"]
    bodies = [Rig(path) for path in (args.body or BODIES)]
    report = json.loads(args.report.read_text(encoding="utf-8")) if args.report else {}
    args.out.mkdir(parents=True, exist_ok=True)

    with tempfile.TemporaryDirectory() as folder:
        folder = Path(folder)
        jobs = {"size": list(CELL), "top_size": list(TOP_CELL), "bodies": []}
        columns = names + ([f"library {replaces}"] if replaces else [])
        numbers, shots_of = {}, {}
        for b, rig in enumerate(bodies):
            clips = review_clips(rig, review)
            old = library_clip(rig, replaces, "Library")
            if old:
                clips.append(old)
            preview = folder / f"{rig.path.stem}.glb"
            preview.write_bytes(export.model_with_clips_bytes(rig, clips))
            shots = []
            for clip in clips:
                record = records.get(clip["name"], {})
                last = clip["rotation"].shape[0] - 1
                speed = args.speed if args.speed is not None else record.get("speed", 0.0)
                if b == 0:
                    for k in range(args.frames):
                        frame = int(round(last * k / args.frames))
                        for view in VIEWS:
                            out = folder / f"{clip['name']}_{view}_{k}.png"
                            shots.append({"clip": clip["name"], "frame": frame, "view": view, "out": out.as_posix(), "shift": speed * frame / 30.0})
                            shots_of[(clip["name"], view, k)] = (out, frame)
                if clip["name"] != "Library":
                    frame = int(round(last * 0.45))
                    out = folder / f"{clip['name']}_body_{b}.png"
                    shots.append({"clip": clip["name"], "frame": frame, "view": "front", "out": out.as_posix(), "shift": 0.0})
                    shots_of[(clip["name"], "body", b)] = (out, frame)
            jobs["bodies"].append({"glb": preview.as_posix(), "shots": shots})
            if b == 0:
                glb = audit_clips.Glb(preview)
                for anim in glb.json["animations"]:
                    row = audit_clips.measure_clip(glb, anim, rig.body)
                    numbers[row["clip"]] = row
        job_file = folder / "jobs.json"
        job_file.write_text(json.dumps(jobs), encoding="utf-8")
        command = [args.blender, "-b", "--factory-startup", "-P", str(HERE / "review_render.py"), "--", job_file.as_posix()]
        done = subprocess.run(command, capture_output=True, text=True, timeout=3600, env=QUIET)
        if "RENDERED" not in done.stdout:
            print(done.stdout[-3000:], done.stderr[-3000:])
            return 1

        # ---- the numbers ----
        keys = names + (["Library"] if replaces else [])
        table = [["measure"] + columns + ["limit"]]
        standing = records[names[0]]["kind"] == "stand"
        for key, label, limit in ROWS:
            if all(numbers[k].get(key) is None for k in keys) or (standing and key in GAIT_ROWS):
                continue
            table.append([label] + [fmt(numbers[k].get(key)) for k in keys] + [limit])
        for path, label, limit in REPORT_ROWS:
            values = []
            for k in keys:
                value = report.get(k)
                for step in path:
                    value = value.get(step) if isinstance(value, dict) else None
                values.append(fmt(value))
            if any(v != "-" for v in values):
                table.append([label] + values + [limit])
        for rig in bodies:
            values = [fmt((report.get(k, {}).get("limbs", {}).get(rig.path.stem) or {}).get("deepest_mm")) for k in keys]
            if any(v != "-" for v in values):
                table.append([f"limbs inside limbs, {rig.path.stem} (mm)"] + values + ["at most 5"])
        lines = ["| " + " | ".join(table[0]) + " |", "|" + " --- |" * len(table[0])]
        lines += ["| " + " | ".join(row) + " |" for row in table[1:]]
        (args.out / f"{args.type}_numbers.md").write_text("\n".join(lines) + "\n", encoding="utf-8", newline="\n")

        # ---- the sheet ----
        pad, label_w, head = 12, 70, 54
        column_w = args.frames * CELL[0] + pad
        strip_h = head + 2 * CELL[1] + TOP_CELL[1] + 3 * pad
        body_h = 40 + CELL[1] + pad
        row_h = 24
        table_h = 40 + row_h * len(table) + pad
        note_h = 40 + 26 * 3 * len(names) + pad
        width = label_w + len(columns) * column_w + pad
        sheet = Image.new("RGB", (width, strip_h + body_h + table_h + note_h), PAPER)
        draw = ImageDraw.Draw(sheet)
        for c, column in enumerate(columns):
            key = keys[c]
            x0 = label_w + c * column_w
            letter = key.rsplit("_", 1)[-1]
            title = f"{key}  ({styles[letter].name})" if letter in styles and key != "Library" else column
            text(draw, (x0, 8), title, 22)
            y = head
            for view in VIEWS:
                cell = TOP_CELL if view == "top" else CELL
                for k in range(args.frames):
                    path, frame = shots_of[(key, view, k)]
                    sheet.paste(Image.open(path).convert("RGB"), (x0 + k * CELL[0], y))
                    if view == "side":
                        text(draw, (x0 + k * CELL[0] + 6, head - 20), f"frame {frame}", 14, FAINT)
                if c == 0:
                    text(draw, (10, y + cell[1] // 2), view, 18)
                y += cell[1] + pad
        y = strip_h
        text(draw, (10, y + 6), "Other bodies: the same frame of each variant on every body", 20)
        x = label_w
        for name in names:
            for b, rig in enumerate(bodies):
                path, frame = shots_of[(name, "body", b)]
                sheet.paste(Image.open(path).convert("RGB"), (x, y + 40))
                text(draw, (x + 6, y + 44), f"{name} on {rig.path.stem.replace('mannequin_', '')}, frame {frame}", 14, FAINT)
                x += CELL[0] + 4
            x += pad
        y += body_h
        text(draw, (10, y + 6), "The numbers (audit_clips.py and the build's checks), with the limits", 20)
        widths = [330] + [(width - 330 - 330 - 2 * pad) // len(columns)] * len(columns) + [330]
        for r, row in enumerate(table):
            x = pad
            for value, w in zip(row, widths):
                text(draw, (x, y + 40 + r * row_h), value, 16, FAINT if r == 0 else INK)
                x += w
        y += table_h
        text(draw, (10, y + 6), "Notes", 20)
        line = y + 40
        for name in names:
            one = styles[name.rsplit("_", 1)[-1]]
            for words in [f"{name}, {one.name}: {one.vision}"] + one.notes(args.type):
                text(draw, (pad, line), words, 16)
                line += 26
        out = args.out / f"{args.type}_sheet.png"
        sheet.save(out)
    print(f"SHEET {out}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
