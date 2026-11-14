"""Which test scripts each `template-tests` shard of the kit's CI runs, and whether a job stayed inside its time limit.

    python3 ci_test_shards.py deal --root <game> --shard 2     # prints "-a res://tests/x/test_a.gd -a ..."
    python3 ci_test_shards.py report --root <game>             # the seconds each shard is expected to take
    python3 ci_test_shards.py self-test --root <game> --workflow .github/workflows/ci.yml
    python3 ci_test_shards.py check --elapsed 812 --limit-minutes 25 --log tests.log --summary "$GITHUB_STEP_SUMMARY"
    python3 ci_test_shards.py update <job log> [<job log> ...]   # rewrite ci_test_times.json from green runs

3D Third Person's GdUnit4 suite outgrew one job (kit #1492: 30 of the job's 40 minutes, cancelled at 40 on a slow
runner). Every `tests/**/test_*.gd` of the made game is one item of work weighted by its seconds in
`ci_test_times.json`, or by `default_seconds` when it has none yet; the items are dealt heaviest first to the shard with
the least so far, so the shards are balanced by measured seconds, not by folder, and a new script lands in the lightest
shard without anyone naming it. The result depends only on the file list and the times file, so every shard agrees
(docs/engines/godot/test-speed.md#split-the-suite-by-seconds-not-by-folder, after Deadnight #1015).

`check` ends every shard and the `template` job: a warning past 60 % of the job's limit and a failure past 80 %, so a
drifting job is red before the limit cancels it with no failing test. To rebalance, download the `template-tests` job
logs of two or more green `main` runs (`gh api repos/<owner>/<repo>/actions/jobs/<id>/logs`), run `update` on them and
commit the times file; add a shard (`SHARDS` here and the workflow's matrix) when `report` flags one over the budget.
"""

from __future__ import annotations

import argparse
import json
import re
import statistics
import sys
from pathlib import Path

# 1,392 s of suites in four green `main` runs (1,077 to 1,576 s; kit #1492), and #1369's `test_jump_weapon_hold.gd`
# adds 526 to 877 s by itself. total / 480 s rounds up to 3, and runners differ by 1.5x from job to job: four shards
# take 270 to 400 s of suites each, 6 to 9 minutes with the minute or two of setup.
SHARDS = 4
# The `template-tests` job's `timeout-minutes`: the heaviest single script on the slowest runner seen (877 s) plus the
# setup stays under 80 % of it.
JOB_LIMIT_MINUTES = 25
WARN_SHARE = 0.6
FAIL_SHARE = 0.8
# `report` flags a shard whose suites are expected to take more than this (a slow runner takes 1.5x).
REPORT_SHARD_BUDGET = 480.0
TIMES_FILE = Path(__file__).with_name("ci_test_times.json")
JOB = "template-tests"

ANSI = re.compile(r"\x1b\[[0-9;]*m")
SUITE = re.compile(r"Run Test Suite: res://tests/(\S+\.gd)")
STATISTICS = re.compile(r"Statistics:.*\|\s*(?:PASSED|FAILED)\s+(.+?)\s*$")
DURATION = re.compile(r"(\d+)\s*(h|min|ms|s)\b")
UNIT_SECONDS = {"h": 3600.0, "min": 60.0, "s": 1.0, "ms": 0.001}


def scripts(root: Path) -> list[str]:
    """Every test script of the game, as a path under tests/ (what GdUnit4 runs: `test_*.gd`, in any subfolder)."""
    tests = root / "tests"
    return sorted(path.relative_to(tests).as_posix() for path in tests.rglob("test_*.gd"))


def load_times(times_file: Path = TIMES_FILE) -> dict:
    return json.loads(times_file.read_text(encoding="utf-8"))


def weights(names: list[str], times: dict) -> dict[str, float]:
    known = times["seconds"]
    default = float(times["default_seconds"])
    return {name: float(known.get(name, default)) for name in names}


def deal(weight: dict[str, float], shards: int = SHARDS) -> tuple[dict[str, int], list[float]]:
    """Longest first to the lightest shard. Returns (shard of each script, expected seconds of each shard)."""
    load = [0.0] * shards
    shard_of: dict[str, int] = {}
    for name, seconds in sorted(weight.items(), key=lambda item: (-item[1], item[0])):
        lightest = min(range(shards), key=lambda index: (load[index], index))
        load[lightest] += seconds
        shard_of[name] = lightest + 1
    return shard_of, load


def shard_paths(names: list[str], times: dict, shard: int, shards: int = SHARDS) -> list[str]:
    if not 1 <= shard <= shards:
        raise SystemExit(f"shard {shard} is not between 1 and {shards}")
    shard_of, _ = deal(weights(names, times), shards)
    return [f"res://tests/{name}" for name in sorted(shard_of) if shard_of[name] == shard]


def report(names: list[str], times: dict) -> str:
    weight = weights(names, times)
    shard_of, load = deal(weight)
    unknown = sorted(name for name in weight if name not in times["seconds"])
    lines = [f"{len(weight)} scripts, {sum(weight.values()):.0f} s of suites, {SHARDS} shards"]
    for shard, seconds in enumerate(load, start=1):
        count = sum(1 for value in shard_of.values() if value == shard)
        flag = ""
        if seconds > REPORT_SHARD_BUDGET:
            flag = "  <- over the budget: " + ("add a shard" if count > 1 else "one script: make it faster")
        lines.append(f"  shard {shard}: {seconds:5.0f} s expected, {count:3d} scripts{flag}")
    lines.append(f"{len(unknown)} scripts have no time yet (counted at {times['default_seconds']} s); the slowest:")
    for name, seconds in sorted(weight.items(), key=lambda item: (-item[1], item[0]))[:10]:
        lines.append(f"  {seconds:6.1f} s  shard {shard_of[name]}  {name}")
    return "\n".join(lines)


def workflow_job(text: str, job: str = JOB) -> str:
    """The text of one job of a workflow file (from its `  <job>:` line to the next job)."""
    match = re.search(rf"^  {re.escape(job)}:\n(.*?)(?=^  \S[^\n]*:\n|\Z)", text, re.MULTILINE | re.DOTALL)
    if not match:
        raise AssertionError(f"the workflow has no `{job}` job")
    return match.group(1)


def check_workflow(text: str) -> None:
    """The workflow runs the shards this file deals, under the limit `check` assumes."""
    job = workflow_job(text)
    matrix = re.search(r"shard: \[([\d, ]+)\]", job)
    assert matrix, f"the workflow's {JOB} job has no `shard: [...]` matrix"
    listed = [int(n) for n in matrix.group(1).split(",")]
    assert listed == list(range(1, SHARDS + 1)), f"the workflow runs shards {listed}, ci_test_shards.py deals {SHARDS}"
    limit = re.search(r"^    timeout-minutes: (\d+)", job, re.MULTILINE)
    assert limit and int(limit.group(1)) == JOB_LIMIT_MINUTES, (
        f"the {JOB} job's timeout-minutes is not ci_test_shards.JOB_LIMIT_MINUTES ({JOB_LIMIT_MINUTES})"
    )
    assert f"--limit-minutes {JOB_LIMIT_MINUTES}" in job, f"the {JOB} job's time check names another limit"
    assert job.count(f"/{SHARDS}") >= 2, f"the {JOB} job's name and check label must say /{SHARDS}"


def self_test(names: list[str], times: dict, workflow: Path | None) -> str:
    assert names, "no test scripts found"
    seen: list[str] = []
    for shard in range(1, SHARDS + 1):
        found = shard_paths(names, times, shard)
        assert found, f"shard {shard} runs nothing"
        seen.extend(found)
    assert sorted(seen) == sorted(f"res://tests/{name}" for name in names), "a script is in no shard, or in two"
    assert float(times["default_seconds"]) > 0, "default_seconds must be above zero"
    assert all(float(s) >= 0 for s in times["seconds"].values()), "a negative time in the times file"
    if workflow is not None:
        check_workflow(workflow.read_text(encoding="utf-8"))
    return f"ok: {len(names)} scripts in {SHARDS} shards"


def seconds_of(text: str) -> float:
    return sum(int(value) * UNIT_SECONDS[unit] for value, unit in DURATION.findall(text))


def suite_seconds(log_text: str) -> dict[str, float]:
    """Each suite's seconds from a GdUnit4 log: the `Statistics:` line after its `Run Test Suite:` line (a job log
    downloaded from GitHub, with its timestamps and colours, or the step's own `tests.log`)."""
    found: dict[str, float] = {}
    current: str | None = None
    for raw in log_text.splitlines():
        line = ANSI.sub("", raw)
        suite = SUITE.search(line)
        if suite:
            current = suite.group(1)
            continue
        stats = STATISTICS.search(line)
        if stats and current:
            found[current] = seconds_of(stats.group(1))
            current = None
    return found


def check(elapsed: float, limit_minutes: float, label: str, log_text: str | None) -> tuple[int, list[str], list[str]]:
    """(exit code, workflow commands to print, job summary lines) for a job that took `elapsed` seconds."""
    limit = limit_minutes * 60.0
    share = elapsed / limit
    minutes = f"{elapsed / 60:.1f} of {limit_minutes:g} minutes ({share:.0%})"
    summary = [f"### {label}: {minutes}", ""]
    if share > FAIL_SHARE:
        code, commands = (
            1,
            [f"::error::{label} took {minutes}, past {FAIL_SHARE:.0%} of its limit: rebalance or add a shard"],
        )
    elif share > WARN_SHARE:
        code, commands = (
            0,
            [f"::warning::{label} took {minutes}, past {WARN_SHARE:.0%} of its limit"],
        )
    else:
        code, commands = 0, [f"{label} took {minutes}"]
    if log_text:
        slowest = sorted(suite_seconds(log_text).items(), key=lambda item: (-item[1], item[0]))[:10]
        if slowest:
            summary += ["| Suite | Seconds |", "| --- | ---: |"]
            summary += [f"| `{name}` | {seconds:.1f} |" for name, seconds in slowest]
    return code, commands, summary


def update(logs: list[Path], times: dict) -> dict:
    """The times file with each script's median seconds over the logs; scripts no log ran keep their old time."""
    runs = [suite_seconds(path.read_text(encoding="utf-8", errors="replace")) for path in logs]
    names = set().union(*runs) if runs else set()
    seconds = dict(times["seconds"])
    for name in names:
        seconds[name] = round(statistics.median(run[name] for run in runs if name in run), 1)
    return {**times, "seconds": dict(sorted(seconds.items()))}


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    sub = parser.add_subparsers(dest="command", required=True)
    for name in ("deal", "report", "self-test"):
        command = sub.add_parser(name)
        command.add_argument(
            "--root",
            type=Path,
            required=True,
            help="the made game's Godot project folder",
        )
        command.add_argument("--times", type=Path, default=TIMES_FILE)
        if name == "deal":
            command.add_argument("--shard", type=int, required=True)
        if name == "self-test":
            command.add_argument("--workflow", type=Path, help="the kit's ci.yml, to compare its matrix")
    timing = sub.add_parser("check")
    timing.add_argument(
        "--elapsed",
        type=float,
        required=True,
        help="seconds since the job's first step",
    )
    timing.add_argument("--limit-minutes", type=float, required=True, help="the job's timeout-minutes")
    timing.add_argument("--label", default="this job")
    timing.add_argument("--log", type=Path, help="the GdUnit4 log, for the slowest suites")
    timing.add_argument("--summary", type=Path, help="the job summary file ($GITHUB_STEP_SUMMARY)")
    refresh = sub.add_parser("update")
    refresh.add_argument("logs", type=Path, nargs="+")
    refresh.add_argument("--times", type=Path, default=TIMES_FILE)
    args = parser.parse_args(argv)

    if args.command == "check":
        log_text = args.log.read_text(encoding="utf-8", errors="replace") if args.log and args.log.is_file() else None
        code, commands, summary = check(args.elapsed, args.limit_minutes, args.label, log_text)
        print("\n".join(commands))
        if args.summary:
            with args.summary.open("a", encoding="utf-8") as out:
                out.write("\n".join(summary) + "\n\n")
        return code
    if args.command == "update":
        data = update(args.logs, load_times(args.times))
        args.times.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")
        print(f"{len(data['seconds'])} scripts timed in {args.times}")
        return 0
    names, times = scripts(args.root), load_times(args.times)
    if args.command == "deal":
        print(" ".join(f"-a {path}" for path in shard_paths(names, times, args.shard)))
    elif args.command == "report":
        print(report(names, times))
    else:
        print(self_test(names, times, args.workflow))
    return 0


if __name__ == "__main__":
    sys.exit(main())
