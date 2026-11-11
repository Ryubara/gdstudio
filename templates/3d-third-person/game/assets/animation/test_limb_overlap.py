"""Test that `limb_overlap.py` reads the same depth from the command line as inside a build (kit #1035).

Run it with the pinned Blender, headless (`gds tool path blender`):

    blender -b --factory-startup -P test_limb_overlap.py [-- --model <body.glb> ...] [--script <limb_overlap.py>]

It runs on the template's bodies by default (`MODELS`: the prototype `form` pair, kit #1286), or on each `--model`.
For each body and each frame rate in `RATES` it keys a clip on the body in which the left thigh swings through the right one
and back within four frames, measures it the way a build does (`measure()` on the action, every frame of a scene at
the clip's rate), exports it, and measures the file with the command line in a new Blender. Both must name the same
deepest frame and read the same depth on every frame. The swing peaks on frame 7, which a 30 frames a second clip
read into a scene at 24 never samples (its whole frames fall at 6.25 and 7.5), so a command line that samples at
the wrong rate reads a shallower crossing on another frame. `--script` names another copy of the script to run as
the command line (the one from before a fix, to see this test fail). Exits 1 on a difference.
"""

import argparse
import json
import subprocess
import sys
import tempfile
from pathlib import Path

import bpy
from mathutils import Matrix

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import limb_overlap  # noqa: E402

RATES = (30, 24)
## The template's bodies (`CharacterBodies` in Godot): the prototype male's thighs meet by 1.9 mm at rest, which the
## swing's depth includes on every frame alike.
MODELS = [HERE.parent / "characters" / "prototype" / f"form_{body}.glb" for body in ("female", "male")]
LAST = 14  # the clip's last frame
PEAK = 7  # the frame the thigh is deepest on
SWING = 0.5  # radians at the peak (the script's own self-test reads over 20 mm there)
CLOSE_MM = 0.2  # the two ways round to 0.1 mm each


def key_swing(body):
    """Key the left thigh through the right one: nothing until two frames before `PEAK`, then in and out."""
    arm = body.arm
    bones = arm.data.bones
    side = bones["thigh_r"].head_local - bones["thigh_l"].head_local
    down = bones["calf_l"].head_local - bones["thigh_l"].head_local
    axis = down.cross(side).normalized()
    rest = bones["thigh_l"].matrix_local
    pivot = Matrix.Translation(rest.translation)
    thigh = arm.pose.bones["thigh_l"]
    thigh.rotation_mode = "QUATERNION"
    for frame in range(LAST + 1):
        angle = SWING * max(0.0, 1.0 - abs(frame - PEAK) / 2.0)
        thigh.matrix = pivot @ Matrix.Rotation(angle, 4, axis) @ pivot.inverted() @ rest
        bpy.context.view_layer.update()
        thigh.keyframe_insert("rotation_quaternion", frame=frame)
    action = arm.animation_data.action
    action.name = "Swing"
    return action


def both_ways(rate, model, script, folder):
    """The report of the in-build call and of the command line for the same clip keyed at `rate`."""
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    scene.render.fps = rate
    scene.frame_start, scene.frame_end = 0, LAST
    body = limb_overlap.load_body(model)
    action = key_swing(body)
    inside = limb_overlap.measure(body.arm, action, range(LAST + 1), [body])[body.name]

    clips = folder / f"swing_{rate}.glb"
    bpy.ops.object.select_all(action="DESELECT")
    for obj in (body.arm, body.mesh):
        obj.select_set(True)
    bpy.context.view_layer.objects.active = body.arm
    bpy.ops.export_scene.gltf(
        filepath=str(clips),
        export_format="GLB",
        use_selection=True,
        export_animations=True,
        export_animation_mode="ACTIONS",
        export_force_sampling=True,
        export_optimize_animation_size=False,
        export_materials="NONE",
    )
    out = folder / f"swing_{rate}.json"
    command = [bpy.app.binary_path, "-b", "--factory-startup", "-P", str(script), "--"]
    command += ["--clips", str(clips), "--model", str(model), "--limit", "1000", "--json", str(out)]
    run = subprocess.run(command, capture_output=True, text=True, timeout=600, check=False)
    assert out.exists(), f"the command line wrote no report:\n{run.stdout[-2000:]}\n{run.stderr[-2000:]}"
    report = json.loads(out.read_text(encoding="utf-8"))
    assert list(report) == ["Swing"], f"the file's clips are {list(report)}"
    outside = report["Swing"][body.name]
    return inside, outside, limb_overlap.clip_rate(clips)


def main():
    argv = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    parser = argparse.ArgumentParser()
    parser.add_argument("--model", action="append", default=[])
    parser.add_argument("--script", default=str(HERE / "limb_overlap.py"))
    args = parser.parse_args(argv)
    faults = []
    with tempfile.TemporaryDirectory() as folder:
        for model, rate in ((m, r) for m in args.model or [str(m) for m in MODELS] for r in RATES):
            inside, outside, read = both_ways(rate, model, args.script, Path(folder))
            rate_name = f"{Path(model).stem} {rate}"
            print(
                f"BOTHWAYS {Path(model).stem} {rate} fps: in the build {inside['deepest_mm']} mm at frame {inside['frame']} of "
                f"{len(inside['frames'])} frames; command line {outside['deepest_mm']} mm at frame "
                f"{outside['frame']} of {len(outside['frames'])} frames; the file's rate reads {read}"
            )
            assert inside["frame"] == PEAK and inside["deepest_mm"] > 20.0, f"the clip does not cross: {inside}"
            if read != rate:
                faults.append(f"{rate_name} fps: clip_rate reads {read} from the file")
            if len(outside["frames"]) != len(inside["frames"]):
                faults.append(f"{rate_name} fps: {len(outside['frames'])} frames measured, the clip has {LAST + 1}")
            elif max(abs(a - b) for a, b in zip(inside["frames"], outside["frames"], strict=True)) > CLOSE_MM:
                faults.append(f"{rate_name} fps: per frame {outside['frames']}, in the build {inside['frames']}")
            if outside["frame"] != inside["frame"]:
                faults.append(f"{rate_name} fps: deepest at frame {outside['frame']}, in the build {inside['frame']}")
            if abs(outside["deepest_mm"] - inside["deepest_mm"]) > CLOSE_MM:
                faults.append(f"{rate_name} fps: deepest {outside['deepest_mm']} mm, in the build {inside['deepest_mm']}")
    for fault in faults:
        print(f"FAULT {fault}")
    if faults:
        sys.exit("the command line and the in-build call disagree")
    print("BOTHWAYS ok")


if __name__ == "__main__":
    main()
