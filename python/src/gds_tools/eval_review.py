"""The `review` kind of agent evals: a pull request with planted faults, judged by the findings a reviewer reports
(docs/studio/agent-evals.md#a-task).

The task folder holds `inputs/` (what the reviewer gets: the description `pr.md`, the diff `pr.diff`, the files after
the change under `repo/` and the repository's rules) and `faults.toml`, the answer key. The reviewer delivers
`REVIEW.md` (with a `Verdict:` line) and `findings.json`, a list of `{"file", "line", "summary"}`. The check matches
each finding to a planted fault by place (a file and a line near the fault's anchor) and counts the faults found and
the findings that match none, so a reviewer that reports everything scores as badly as one that reports nothing.
"""

from __future__ import annotations

import json
import re
import shutil
import tomllib
from dataclasses import dataclass, field
from pathlib import Path

ALIASES = {
    "description": "pr.md",
    "pr_description": "pr.md",
    "pr body": "pr.md",
    "diff": "pr.diff",
    "pr.patch": "pr.diff",
}
DIFF = "pr.diff"


def prepare(folder: Path, target: Path) -> None:
    """The eval folder of a review task: the brief is already there; the inputs are copied beside it."""
    shutil.copytree(folder / "inputs", target, dirs_exist_ok=True)


@dataclass
class Place:
    """Where a fault or a trap is: a file (by name) and the line of its anchor, within `tol` lines."""

    file: str
    line: int
    tol: int


@dataclass
class Item:
    id: str
    kind: str
    summary: str
    places: list[Place] = field(default_factory=list)


def _line_of(text: str, anchor: str) -> int | None:
    for number, line in enumerate(text.replace("\r\n", "\n").split("\n"), start=1):
        if anchor in line:
            return number
    return None


def _diff_line_of(diff: str, anchor: str) -> int | None:
    for number, line in enumerate(diff.replace("\r\n", "\n").split("\n"), start=1):
        if line.startswith("+") and not line.startswith("+++") and anchor in line:
            return number
    return None


def load_key(folder: Path) -> tuple[list[Item], list[Item]]:
    """(faults, traps) with every anchor resolved to a line of its file and of `pr.diff`; ValueError when an anchor is
    missing or appears in two files of one name."""
    key = tomllib.loads((folder / "faults.toml").read_text(encoding="utf-8"))
    inputs = folder / "inputs"
    files: dict[str, Path] = {}
    for path in sorted(inputs.rglob("*")):
        if path.is_file():
            if path.name in files:
                raise ValueError(f"two input files are named {path.name}")
            files[path.name] = path
    diff = (inputs / DIFF).read_text(encoding="utf-8")
    result: list[list[Item]] = []
    for table, kind in (("fault", None), ("trap", "trap")):
        items = []
        for raw in key.get(table, []):
            item = Item(raw["id"], raw.get("kind", kind or ""), raw["summary"])
            for spot in raw["locations"]:
                name = spot["file"]
                if name not in files:
                    raise ValueError(f"{item.id}: no input file {name}")
                text = files[name].read_text(encoding="utf-8")
                if sum(spot["anchor"] in line for line in text.splitlines()) != 1:
                    raise ValueError(f"{item.id}: the anchor {spot['anchor']!r} is not in {name} exactly once")
                line = _line_of(text, spot["anchor"])
                item.places.append(Place(name.lower(), line, spot.get("tol", 0)))
                in_diff = _diff_line_of(diff, spot["anchor"])
                if in_diff is not None:
                    item.places.append(Place(DIFF, in_diff, spot.get("tol", 0)))
            items.append(item)
        result.append(items)
    return result[0], result[1]


def _name(raw: object) -> str:
    text = str(raw).replace("\\", "/").strip().lower()
    base = text.rsplit("/", 1)[-1]
    return ALIASES.get(base, ALIASES.get(text, base))


def _line(raw: object) -> int | None:
    if isinstance(raw, bool):
        return None
    if isinstance(raw, int):
        return raw
    if isinstance(raw, list) and raw:
        return _line(raw[0])
    found = re.search(r"\d+", str(raw))
    return int(found.group()) if found else None


def parse_findings(text: str) -> tuple[list[dict], list[str]]:
    """(findings with a name, a line and a summary, problems with the file or with single findings)."""
    try:
        data = json.loads(text)
    except ValueError as error:
        return [], [f"findings.json is not JSON: {error}"]
    if isinstance(data, dict):
        data = data.get("findings", [])
    if not isinstance(data, list):
        return [], ["findings.json is not a list"]
    good, problems = [], []
    for index, entry in enumerate(data, start=1):
        line = _line(entry.get("line")) if isinstance(entry, dict) else None
        summary = entry.get("summary") if isinstance(entry, dict) else None
        if not isinstance(entry, dict) or not entry.get("file") or line is None or not isinstance(summary, str):
            problems.append(f"finding {index} needs a file, a line number and a summary")
            continue
        good.append({"file": _name(entry["file"]), "line": line, "summary": summary})
    return good, problems


def _nearest(items: list[Item], finding: dict) -> tuple[Item | None, int]:
    best: tuple[Item | None, int] = (None, 10**9)
    for item in items:
        for place in item.places:
            gap = abs(place.line - finding["line"])
            if place.file == finding["file"] and gap <= place.tol and gap < best[1]:
                best = (item, gap)
    return best


def score(folder: Path, findings: list[dict]) -> dict:
    """Match the findings to the key: faults found, duplicates, findings that match none and the traps among them."""
    faults, traps = load_key(folder)
    found: dict[str, int] = {}
    duplicates = 0
    false, on_traps = 0, 0
    for finding in findings:
        fault, _ = _nearest(faults, finding)
        if fault is not None:
            duplicates += fault.id in found
            found[fault.id] = found.get(fault.id, 0) + 1
            continue
        false += 1
        if _nearest(traps, finding)[0] is not None:
            on_traps += 1
    kinds: dict[str, list[int]] = {}
    for fault in faults:
        kinds.setdefault(fault.kind, [0, 0])
        kinds[fault.kind][1] += 1
        kinds[fault.kind][0] += fault.id in found
    return {
        "found": len(found),
        "planted": len(faults),
        "false": false,
        "traps": on_traps,
        "duplicates": duplicates,
        "kinds": ", ".join(f"{kind} {got}/{total}" for kind, (got, total) in sorted(kinds.items())),
        "found_ids": sorted(found),
    }


def _row(rows: list[dict], name: str, value, op: str, limit) -> None:
    ok = {"==": lambda: value == limit, "<=": lambda: value <= limit, ">=": lambda: value >= limit}[op]()
    rows.append({"name": name, "value": value, "op": op, "limit": limit, "unit": "", "pass": bool(ok)})


def check_review(name: str, folder: Path, target: Path, limits: dict) -> dict:
    """Measure `REVIEW.md` and `findings.json` in `target`; the rows in the shape every check writes."""
    rows: list[dict] = []
    errors: list[str] = []
    review = target / "REVIEW.md"
    text = review.read_text(encoding="utf-8", errors="replace") if review.is_file() else ""
    verdict = re.search(r"verdict:?\**\s*:?\s*\**\s*changes needed", text, re.IGNORECASE) is not None
    _row(rows, "REVIEW.md gives the verdict `changes needed`", verdict, "==", True)
    path = target / "findings.json"
    findings, problems = (
        parse_findings(path.read_text(encoding="utf-8")) if path.is_file() else ([], ["no findings.json"])
    )
    errors += problems
    _row(
        rows,
        "findings.json lists findings with a file, a line and a summary",
        not problems and bool(findings),
        "==",
        True,
    )
    result = score(folder, findings)
    _row(rows, "planted faults found", result["found"], ">=", limits.get("min_found", 9))
    _row(rows, "findings that match no planted fault", result["false"], "<=", limits.get("max_false", 2))
    _row(rows, "findings in all", len(findings), "<=", limits.get("max_findings", 25))
    for label, value in (
        ("planted faults in the pull request", result["planted"]),
        ("faults found, by kind", result["kinds"]),
        ("false findings on code that is correct", result["traps"]),
        ("findings that repeat a fault already found", result["duplicates"]),
    ):
        rows.append({"name": label, "value": value, "op": "info", "limit": "", "unit": "", "pass": True})
    return {"task": name, "passed": sum(r["pass"] for r in rows), "total": len(rows), "rows": rows, "errors": errors}
