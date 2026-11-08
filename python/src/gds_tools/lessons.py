"""Topic sections, the entries that record what was learned, the checks of their format, `gds learn`, and the
mistakes glossary built from them.

What was learned goes into the topic page agents read for that task, as a short entry in the page's own voice
(docs/studio/rules.md): `- **Approach:** ... **Watch out for:** ... **Seen:** ...`, in a `##`/`###` section with an
explicit `{#anchor}`, named elsewhere as `page.md#anchor`. There are no lesson pages. This module reads the sections
and entries of the docs, finds the ones closest to some words (`gds learn`), and checks the format (`problems`, and
`base_problems` against the base of a pull request): no new file under the old `docs/lessons/` folder, no page past
its size, no new section without a reason line, no malformed entry or anchor, and no corrections-log row that quotes
the maintainer or links no section.

The old lesson files (`docs/lessons/<date>-<slug>.md`, `areas:` front matter) keep building until gdstudio #770
empties the folder. The glossary (`gds lessons <area>`, the SubagentStart hook) is built in memory from the entries of
the sections and those old files, never written to a file. Standard library only: the hooks load this file by path.
"""

from __future__ import annotations

import math
import re
import subprocess
import tomllib
import unicodedata
from dataclasses import dataclass
from pathlib import Path

GENERAL = "general"
DOCS = Path("docs")
AREAS_FILE = DOCS / "lessons" / "areas.toml"
CORRECTIONS = DOCS / "studio" / "maintainer-corrections.md"
LESSONS = DOCS / "lessons"
RULES_DOC = DOCS / "studio" / "rules.md"

#: `learning` of .github/conventions.yml (a test keeps them equal).
MAX_PAGE_KB = 50
MAX_RULE_CHARS = 900
RULE_PARTS = ("Approach:", "Watch out for:", "Seen:")
REASON_LINE = "<!-- new section:"
LEGACY_LAST_DATE = "2026-11-07"

_FRONT = re.compile(r"\A---\n(.*?)\n---\n", re.DOTALL)
_AREAS_LINE = re.compile(r"^areas:\s*\[(.*?)\]\s*$", re.MULTILINE)
_LINK = re.compile(r"\[([^\]]*)\]\([^)]*\)")
_HEADING = re.compile(r"^(#{1,6})\s+(.+?)\s*#*\s*$")
_ATTRS = re.compile(r"\s*\{:?([^{}]*)\}\s*$")
_ANCHOR = re.compile(r"[a-z0-9]+(?:-[a-z0-9]+)*")
_FENCE = re.compile(r"^\s*(```|~~~)")
_RULE_START = re.compile(r"^- \*\*Approach:\*\*")
_OLD_RULE = re.compile(r"^- \*\*Rule:\*\*")
_REF = re.compile(r"((?:[\w.-]+/)*[\w.-]+\.md)#([A-Za-z0-9_-]+)")
_SEEN_SOURCE = re.compile(r"#\d+|20\d\d-\d\d-\d\d|github\.com/")
_LESSON_DATE = re.compile(r"^(20\d\d-\d\d-\d\d)-")


class LessonsError(Exception):
    """The lessons or the glossary are inconsistent."""


@dataclass(frozen=True)
class Areas:
    """`docs/lessons/areas.toml`: the area names with their descriptions, the label map, the placement keywords and
    the page prefixes whose rules belong to an area."""

    names: dict[str, str]
    labels: dict[str, list[str]]
    keywords: dict[str, list[str]]
    pages: dict[str, list[str]] | None = None

    @classmethod
    def load(cls, path: Path) -> Areas:
        data = tomllib.loads(path.read_text(encoding="utf-8"))
        return cls(
            dict(data["areas"]),
            dict(data.get("labels", {})),
            dict(data.get("keywords", {})),
            dict(data.get("pages", {})),
        )

    def for_labels(self, labels: list[str] | set[str] | frozenset[str]) -> list[str]:
        """The areas of an issue's labels, in the order of the label map; `general` is always there."""
        found = [GENERAL]
        for label in sorted(labels):
            found += [a for a in self.labels.get(label, []) if a not in found]
        return found

    def classify(self, text: str) -> list[str]:
        """The (at most two) areas whose keywords the text mentions most; `general` when none does."""
        lower = f" {text.lower()} "
        scores = {a: sum(lower.count(k) for k in words) for a, words in self.keywords.items() if a in self.names}
        best = sorted((a for a, s in scores.items() if s), key=lambda a: (-scores[a], list(self.names).index(a)))
        return best[:2] or [GENERAL]

    def for_page(self, page: str, text: str) -> list[str]:
        """The areas of a rule on `page` (a path under docs/): the longest prefix of `[pages]`, else by keyword."""
        prefixes = sorted((p for p in (self.pages or {}) if page.startswith(p)), key=len, reverse=True)
        return [a for a in (self.pages or {})[prefixes[0]] if a in self.names] if prefixes else self.classify(text)


# --------------------------------------------------------------------------------------------------------------------
# Sections, rules and anchors (docs/studio/rules.md)
# --------------------------------------------------------------------------------------------------------------------


@dataclass(frozen=True)
class Section:
    """One heading of a topic page and the text under it, up to the next heading."""

    page: str  # the path under docs/, with forward slashes
    level: int
    title: str
    anchor: str
    explicit: bool  # the heading carries its own `{#anchor}`
    line: int  # 1-based line of the heading
    body: str

    @property
    def ref(self) -> str:
        return f"{self.page}#{self.anchor}"

    def rules(self) -> list[str]:
        return [text for _, text in rule_items(self.body)]


def implicit_anchor(title: str) -> str:
    """The anchor the docs build gives a heading without its own (Python-Markdown's `toc` slug of its words)."""
    text = _LINK.sub(r"\1", title).replace("`", "")
    text = unicodedata.normalize("NFKD", text).encode("ascii", "ignore").decode("ascii")
    return re.sub(r"[-\s]+", "-", re.sub(r"[^\w\s-]", "", text).strip().lower())


def _heading(line: str) -> tuple[int, str, str, bool] | None:
    """(level, title, anchor, explicit) of a Markdown heading line, None for any other line."""
    found = _HEADING.match(line)
    if not found:
        return None
    title, anchor, explicit = found.group(2), "", False
    attrs = _ATTRS.search(title)
    if attrs:
        title = title[: attrs.start()].rstrip()
        named = re.search(r"#(\S+)", attrs.group(1))
        if named:
            anchor, explicit = named.group(1), True
    return len(found.group(1)), title, anchor or implicit_anchor(title), explicit


def _outside_code(text: str) -> list[tuple[int, str]]:
    """(1-based number, line) of every line outside fenced code blocks."""
    out, fenced = [], False
    for number, line in enumerate(text.replace("\r\n", "\n").split("\n"), 1):
        if _FENCE.match(line):
            fenced = not fenced
            continue
        if not fenced:
            out.append((number, line))
    return out


def parse_sections(page: str, text: str) -> list[Section]:
    """Every heading of a page with the text under it (code blocks are not headings)."""
    lines = text.replace("\r\n", "\n").split("\n")
    heads = [(n, h) for n, line in _outside_code(text) if (h := _heading(line))]
    out = []
    for i, (number, (level, title, anchor, explicit)) in enumerate(heads):
        end = heads[i + 1][0] - 1 if i + 1 < len(heads) else len(lines)
        out.append(Section(page, level, title, anchor, explicit, number, "\n".join(lines[number:end])))
    return out


def rule_items(text: str, first_line: int = 1) -> list[tuple[int, str]]:
    """(line, text) of every entry (`- **Approach:** ...` and its indented continuation lines), joined on one line."""
    out: list[tuple[int, list[str]]] = []
    on = False
    for number, line in _outside_code(text):
        if _RULE_START.match(line):
            out.append((number + first_line - 1, [line[2:].strip()]))
            on = True
        elif on and line.startswith("  ") and line.strip():
            out[-1][1].append(line.strip())
        else:
            on = False
    return [(n, " ".join(parts)) for n, parts in out]


def rule_parts(rule: str) -> dict[str, str] | None:
    """The parts of an entry's text (`Approach`, `Watch out for`, `Seen`), None when one is missing or out of order."""
    marks = [f"**{p}**" for p in RULE_PARTS]
    places = [rule.find(m) for m in marks]
    if any(p < 0 for p in places) or places != sorted(places):
        return None
    ends = places[1:] + [len(rule)]
    return {p[:-1]: rule[s + len(m) : e].strip() for p, m, s, e in zip(RULE_PARTS, marks, places, ends, strict=True)}


def anchors(path: Path) -> set[str]:
    """The anchors of a page's headings (explicit or not); empty when the page does not exist."""
    if not path.is_file():
        return set()
    return {s.anchor for s in parse_sections(path.name, path.read_text(encoding="utf-8"))}


def parse_ref(text: str) -> tuple[str, str] | None:
    """(page under docs/, anchor) of the first `page.md#anchor` in a text (a path, a relative link or a URL)."""
    found = refs_in(text)
    return found[0] if found else None


def refs_in(text: str) -> list[tuple[str, str]]:
    """Every `page.md#anchor` of a text as (page under docs/, anchor), in order, without repeats. `docs/`, a URL up to
    it and leading `../` are dropped: `docs/studio/hooks.md#learning` and `studio/hooks.md#learning` are the same."""
    out: list[tuple[str, str]] = []
    for found in _REF.finditer(text):
        page = found.group(1)
        page = page.split("docs/", 1)[1] if "docs/" in page else page
        while page.startswith(("../", "./")):
            page = page.split("/", 1)[1]
        if (page, found.group(2)) not in out:
            out.append((page, found.group(2)))
    return out


def topic_pages(root: Path) -> list[Path]:
    """Every docs page outside the old lessons folder, sorted."""
    return sorted(p for p in (root / DOCS).rglob("*.md") if (root / LESSONS) not in p.parents)


def sections_in(root: Path) -> list[Section]:
    out = []
    for path in topic_pages(root):
        out += parse_sections(path.relative_to(root / DOCS).as_posix(), path.read_text(encoding="utf-8"))
    return out


def page_problems(page: str, text: str) -> list[str]:
    """The format problems of one topic page: its size, its anchors and its rules."""
    found = []
    size = len(text.encode("utf-8"))
    if size > MAX_PAGE_KB * 1024:
        found.append(
            f"docs/{page}: {size // 1024} KB, over the {MAX_PAGE_KB} KB limit; split the topic into a folder of "
            f"subpages ({RULES_DOC.as_posix()}#size)"
        )
    sections = parse_sections(page, text)
    seen: dict[str, int] = {}
    for s in sections:
        if s.explicit and not _ANCHOR.fullmatch(s.anchor):
            found.append(f"docs/{page}:{s.line}: anchor {{#{s.anchor}}} is not lowercase words joined by hyphens")
        if s.anchor in seen and (s.explicit or any(o.explicit and o.anchor == s.anchor for o in sections)):
            found.append(f"docs/{page}:{s.line}: anchor #{s.anchor} is used twice (also line {seen[s.anchor]})")
        seen.setdefault(s.anchor, s.line)
        for number, line in _outside_code(s.body):
            if _OLD_RULE.match(line):
                found.append(
                    f"docs/{page}:{s.line + number}: `- **Rule:** ... **Why:** ... **Fix:**` is the old form; write "
                    f"`- **Approach:** ... **Watch out for:** ... **Seen:** ...` ({RULES_DOC.as_posix()}#rule)"
                )
        for line, rule in rule_items(s.body, s.line + 1):
            where = f"docs/{page}:{line}"
            if s.level < 2 or not s.explicit:
                found.append(f"{where}: a rule sits in a section without an explicit {{#anchor}} (a ## or ### heading)")
            parts = rule_parts(rule)
            if parts is None:
                found.append(f"{where}: an entry has {', '.join(f'**{p}**' for p in RULE_PARTS)} in this order")
            elif not _SEEN_SOURCE.search(parts["Seen"]):
                found.append(f"{where}: the entry's **Seen:** names its issue or pull request (#N) or a date")
            if len(rule) > MAX_RULE_CHARS:
                found.append(f"{where}: the rule has {len(rule)} characters, over {MAX_RULE_CHARS}; keep it short")
    return found


# --------------------------------------------------------------------------------------------------------------------
# The old lessons folder, the corrections log and the checks
# --------------------------------------------------------------------------------------------------------------------


@dataclass(frozen=True)
class Lesson:
    path: Path
    title: str
    areas: list[str]
    fix: str
    cause: str = ""


def split_front_matter(text: str) -> tuple[str, str]:
    """(front matter, body) of a Markdown file; the front matter is '' when the file has none."""
    found = _FRONT.match(text.replace("\r\n", "\n"))
    return (found.group(1), text.replace("\r\n", "\n")[found.end() :]) if found else ("", text.replace("\r\n", "\n"))


def parse_lesson(path: Path) -> Lesson:
    front, body = split_front_matter(path.read_text(encoding="utf-8"))
    line = _AREAS_LINE.search(front)
    areas = [a.strip() for a in line.group(1).split(",") if a.strip()] if line else []
    title = next((ln[2:].strip() for ln in body.splitlines() if ln.startswith("# ")), path.stem)
    return Lesson(path, title, areas, _bullet(body, "Fix"), _bullet(body, "Cause"))


def _bullet(body: str, name: str) -> str:
    """The text of a lesson's `- **<name>...:**` bullet (`**Fix:**`, `**Fix (Deadnight #364):**`), its wrapped lines
    joined."""
    head = re.compile(r"^- \*\*" + name + r"[^:*]*:\*\*\s*(.*)")
    out, on = [], False
    for line in body.splitlines():
        found = head.match(line)
        if found:
            on = True
            out.append(found.group(1).strip())
        elif on and (line.startswith("- **") or not line.strip()):
            break
        elif on:
            out.append(line.strip())
    return " ".join(out)


def lessons_in(root: Path) -> list[Lesson]:
    """Every old lesson file of a kit checkout, oldest first by file name."""
    return [parse_lesson(p) for p in sorted((root / LESSONS).glob("20*.md"))]


def problems(root: Path, areas: Areas) -> list[str]:
    """Everything a checkout alone can show is wrong: old lesson files without areas, naming an unknown area or dated
    after the old folder closed; topic pages past their size or with a malformed anchor or rule; and corrections-log
    rows that quote the maintainer or link no section."""
    found = []
    for lesson in lessons_in(root):
        if not lesson.areas:
            found.append(f"{lesson.path.name}: no `areas: [...]` front matter")
        found += [f"{lesson.path.name}: unknown area {a!r}" for a in lesson.areas if a not in areas.names]
        date = _LESSON_DATE.match(lesson.path.name)
        if date and date.group(1) > LEGACY_LAST_DATE:
            found.append(_new_lesson_message(lesson.path.name))
    for path in topic_pages(root):
        found += page_problems(path.relative_to(root / DOCS).as_posix(), path.read_text(encoding="utf-8"))
    corrections = root / CORRECTIONS
    if corrections.exists():
        text = corrections.read_text(encoding="utf-8")
        found += quoted_rows(text) + unlinked_rows(text)
    return found


def _new_lesson_message(name: str) -> str:
    return (
        f"docs/lessons/{name}: no new file goes in the old lessons folder; write the rule into the topic section it "
        f"belongs to (`gds learn <words>` finds it; {RULES_DOC.as_posix()})"
    )


def backfill(root: Path, areas: Areas) -> list[Path]:
    """Give every old lesson without areas a front-matter line placed by keyword (a script, not by hand). Returns the
    files changed."""
    changed = []
    for path in sorted((root / LESSONS).glob("20*.md")):
        text = path.read_text(encoding="utf-8").replace("\r\n", "\n")
        front, body = split_front_matter(text)
        if _AREAS_LINE.search(front):
            continue
        title = next((ln[2:] for ln in body.splitlines() if ln.startswith("# ")), "")
        placed = areas.classify(f"{title} " * 3 + body[:2500])  # the title counts three times
        line = f"areas: [{', '.join(placed)}]"
        new = f"---\n{front}\n{line}\n---\n{body}" if front else f"---\n{line}\n---\n{text}"
        path.write_text(new, encoding="utf-8", newline="\n")
        changed.append(path)
    return changed


def cells(line: str) -> list[str]:
    return [c.strip() for c in re.split(r"(?<!\\)\|", line.strip().strip("|"))]


def _table_rows(text: str) -> list[tuple[int, str]]:
    """(1-based number, line) of the body rows of every table (header and separator lines are not rows)."""
    rows, header = [], False
    for number, line in enumerate(text.replace("\r\n", "\n").splitlines(), 1):
        if not line.startswith("|"):
            header = False
        elif line.startswith("| ---"):
            continue
        elif not header:
            header = True
        else:
            rows.append((number, line))
    return rows


_QUOTES = "\"'“”‘’«»"  # straight, curly and guillemet quotation marks


def quoted_rows(text: str) -> list[str]:
    """Rows of the corrections log with a cell that starts with a quotation mark. A row says what the maintainer
    pointed out in our words, with its source; the maintainer's prompts are never quoted in a public repository
    (gdstudio #780)."""
    found = []
    for number, line in _table_rows(text):
        quoted = next((c for c in cells(line) if c[:1] in _QUOTES), None)
        if quoted is not None:
            found.append(
                f"{CORRECTIONS.as_posix()}:{number}: the row quotes the maintainer ({quoted[:40]}...); "
                "say what was pointed out in our words, with its source, never the prompt"
            )
    return found


def unlinked_rows(text: str) -> list[str]:
    """Rows of the corrections log whose last cell links no section (`page.md#anchor`): the rule lives there."""
    return [
        f"{CORRECTIONS.as_posix()}:{number}: the row links no section; its last cell names where the rule lives "
        "as a link to page.md#anchor"
        for number, line in _table_rows(text)
        if not refs_in(cells(line)[-1])
    ]


def _git(root: Path, *args: str) -> tuple[int, str]:
    try:
        done = subprocess.run(
            ["git", "-C", str(root), *args], capture_output=True, text=True, encoding="utf-8", timeout=60
        )
    except (OSError, subprocess.SubprocessError) as error:
        return 1, str(error)
    return done.returncode, done.stdout


def default_base(root: Path) -> str | None:
    """Where this branch left origin/main (its merge base), None when origin/main is not known here."""
    code, out = _git(root, "merge-base", "origin/main", "HEAD")
    return out.strip() if code == 0 and out.strip() else None


def default_bases(root: Path) -> list[str]:
    """What the branch is compared with by default: where it left origin/main, and origin/main itself. A heading or a
    lesson file that either has is not the branch's own (in a merge of main, the merge base is still the old main)."""
    base = default_base(root)
    return [base, "origin/main"] if base else []


def base_problems(root: Path, base: str | list[str]) -> list[str]:
    """What the checkout adds against `base` (a commit, or several: what any of them has is not new) that the rules
    refuse: a file in the old lessons folder, and a heading no base page has with no reason line under it. Raises
    LessonsError when a base is unknown."""
    bases = [base] if isinstance(base, str) else list(base)
    for commit in bases:
        code, _ = _git(root, "rev-parse", "--verify", "--quiet", f"{commit}^{{commit}}")
        if code != 0:
            raise LessonsError(f"the base {commit!r} is not a commit here (fetch it, or pass --base)")
    before: set[str] = set()
    for commit in bases:
        _, listed = _git(root, "ls-tree", "-r", "--name-only", commit, "--", LESSONS.as_posix())
        before |= set(listed.split())
    found = [
        _new_lesson_message(p.name)
        for p in sorted((root / LESSONS).glob("*.md"))
        if p.relative_to(root).as_posix() not in before
    ]
    _, changed = _git(root, "diff", "--name-only", bases[0], "--", DOCS.as_posix())
    _, untracked = _git(root, "ls-files", "--others", "--exclude-standard", "--", DOCS.as_posix())
    for name in sorted(set(changed.split()) | set(untracked.split())):
        path = root / name
        if not name.endswith(".md") or not path.is_file() or (root / LESSONS) in path.parents:
            continue
        olds = [text for code, text in (_git(root, "show", f"{commit}:{name}") for commit in bases) if code == 0]
        page = path.relative_to(root / DOCS).as_posix()
        found += new_section_problems(page, "\n".join(olds) if olds else None, path.read_text(encoding="utf-8"))
    return found


def new_section_problems(page: str, old: str | None, new: str) -> list[str]:
    """New headings without a reason line (`<!-- new section: ... -->` as the next line with text). A new page needs
    it under its `#` title; an existing page under each new `##`/`###` heading whose parent heading is not new too."""
    lines = new.replace("\r\n", "\n").split("\n")
    sections = parse_sections(page, new)
    if old is None:
        wanted = [s for s in sections if s.level == 1][:1]
    else:
        known = {s.anchor for s in parse_sections(page, old)}
        wanted, parents = [], {}
        for s in sections:
            is_new = s.anchor not in known
            parents = {lv: n for lv, n in parents.items() if lv < s.level}
            parent_new = bool(parents) and parents[max(parents)]
            if s.level in (2, 3) and is_new and not parent_new:
                wanted.append(s)
            parents[s.level] = is_new and s.level >= 2
    found = []
    for s in wanted:
        after = next((ln.strip() for ln in lines[s.line :] if ln.strip()), "")
        if not after.startswith(REASON_LINE):
            kind = "page" if s.level == 1 else "section"
            found.append(
                f"docs/{page}:{s.line}: the new {kind} '{s.title}' needs a reason line under its heading: "
                f"`{REASON_LINE} why no existing section fits -->` ({RULES_DOC.as_posix()}#section)"
            )
    return found


# --------------------------------------------------------------------------------------------------------------------
# `gds learn`: the existing sections closest to some words
# --------------------------------------------------------------------------------------------------------------------

_STOP = {
    "the",
    "and",
    "for",
    "with",
    "that",
    "this",
    "from",
    "into",
    "onto",
    "over",
    "under",
    "when",
    "what",
    "which",
    "while",
    "where",
    "there",
    "their",
    "them",
    "they",
    "then",
    "than",
    "are",
    "was",
    "were",
    "has",
    "have",
    "had",
    "not",
    "but",
    "its",
    "our",
    "out",
    "who",
    "how",
    "why",
    "all",
    "any",
    "each",
    "one",
    "two",
    "can",
    "may",
    "must",
    "should",
    "would",
    "could",
    "does",
    "did",
    "done",
    "doing",
    "use",
    "used",
    "using",
    "via",
    "per",
    "also",
    "only",
    "very",
    "more",
    "most",
    "less",
    "such",
    "some",
    "same",
    "other",
}


def _stem(word: str) -> str:
    """A crude stem: `-ing`, `-ed`, and a plural's `-es` (after s, x, z, ch, sh) or `-s`."""
    for suffix in ("ing", "ed"):
        if word.endswith(suffix) and len(word) - len(suffix) >= 4:
            return word[: -len(suffix)]
    if word.endswith(("sses", "xes", "zes", "ches", "shes")) and len(word) >= 6:
        return word[:-2]
    if word.endswith("s") and not word.endswith("ss") and len(word) >= 5:
        return word[:-1]
    return word


def terms(text: str) -> list[str]:
    """The search terms of a text: lowercase words of three letters or more, without common words, crudely stemmed."""
    return [_stem(w) for w in re.findall(r"[a-z0-9]+", text.lower()) if len(w) >= 3 and w not in _STOP]


@dataclass(frozen=True)
class Match:
    score: float
    section: Section | None = None
    lesson: Lesson | None = None


def _rank(query: list[str], docs: list[tuple[object, list[str], list[str], list[str]]]) -> list[tuple[float, object]]:
    """BM25 over (item, title terms, path terms, body terms): a title word counts 4, a path word 2, a body word 1, and
    the score is scaled by the share of the query's terms the item has."""
    wanted = list(dict.fromkeys(query))
    if not wanted or not docs:
        return []
    counted = []
    for item, title, path, body in docs:
        tf: dict[str, float] = {}
        for weight, words in ((4.0, title), (2.0, path), (1.0, body)):
            for w in words:
                tf[w] = tf.get(w, 0.0) + weight
        counted.append((item, tf, len(title) * 4 + len(path) * 2 + len(body)))
    total = len(counted)
    average = sum(n for _, _, n in counted) / total or 1.0
    df = {t: sum(1 for _, tf, _ in counted if t in tf) for t in wanted}
    out = []
    for item, tf, length in counted:
        hits = [t for t in wanted if t in tf]
        if not hits:
            continue
        score = 0.0
        for t in hits:
            idf = math.log(1 + (total - df[t] + 0.5) / (df[t] + 0.5))
            score += idf * tf[t] * 2.2 / (tf[t] + 1.2 * (0.25 + 0.75 * length / average))
        out.append((score * len(hits) / len(wanted), item))
    return sorted(out, key=lambda pair: -pair[0])


def learn(root: Path, words: str, limit: int = 5, legacy: int = 0) -> list[Match]:
    """The `limit` sections of the topic pages closest to `words`, best first; then, when asked (`legacy`), the closest
    old lesson files, which #770 empties."""
    query = terms(words)
    skip = {CORRECTIONS.relative_to(DOCS).as_posix(), RULES_DOC.relative_to(DOCS).as_posix()}  # a log, the format
    sections = [s for s in sections_in(root) if s.page not in skip]
    ranked = _rank(query, [(s, terms(s.title), terms(s.page.replace(".md", "")), terms(s.body)) for s in sections])
    out = [Match(score, section=s) for score, s in ranked[:limit]]  # type: ignore[arg-type]
    if legacy:
        files = lessons_in(root)
        texts = [(lesson, lesson.path.read_text(encoding="utf-8")) for lesson in files]
        ranked = _rank(query, [(les, terms(les.title), [], terms(text)) for les, text in texts])
        out += [Match(score, lesson=les) for score, les in ranked[:legacy]]  # type: ignore[arg-type]
    return out


def _first_words(text: str, limit: int) -> str:
    text = " ".join(_LINK.sub(r"\1", text).split())
    return text if len(text) <= limit else text[:limit].rsplit(" ", 1)[0] + " ..."


def learn_text(root: Path, words: str, limit: int = 5, legacy: int = 0, rules_per: int = 4) -> str:
    """What `gds learn` prints: each close section as `page.md#anchor` with its rules (or its first words when it has
    none), then the close old lesson files."""
    matches = learn(root, words, limit, legacy)
    sections = [m.section for m in matches if m.section]
    old = [m.lesson for m in matches if m.lesson]
    if not sections and not old:
        return f"No section mentions {words!r}. Make a new one where it belongs ({RULES_DOC.as_posix()}#section)."
    lines = [
        f"The sections closest to {words!r}, best first. Update one of them (add to an entry's Seen, sharpen it, or "
        f"add an entry) before you make a new section ({RULES_DOC.as_posix()}):"
    ]
    for number, s in enumerate(sections, 1):
        rules = s.rules()
        lines += ["", f"{number}. {s.ref}  {s.title}  (docs/{s.page}:{s.line}, {len(rules)} entr(y/ies))"]
        if rules:
            for rule in rules[:rules_per]:
                parts = rule_parts(rule) or {"Approach": rule}
                lines.append(f"   - {_first_words(parts['Approach'], 220)}")
            if len(rules) > rules_per:
                lines.append(f"   - ... {len(rules) - rules_per} more")
        else:
            body = re.sub(r"<!--.*?-->", "", s.body, flags=re.DOTALL)
            prose = "\n".join(ln for ln in body.split("\n") if ln.strip() and not ln.startswith("|"))
            if prose:
                lines.append(f"   {_first_words(prose, 220)}")
    if old:
        lines += ["", "Old lesson files on the same subject (#770 moves them into sections; fold their point in):"]
        lines += [f"- {les.path.relative_to(root).as_posix()}  {les.title}" for les in old]
    return "\n".join(lines)


# --------------------------------------------------------------------------------------------------------------------
# The glossary: the rules of the sections and the old lesson files, by area
# --------------------------------------------------------------------------------------------------------------------


def brief(text: str, limit: int) -> str:
    """One table cell of text: links reduced to their words, cut at a word near `limit`; `|` and `<` become entities."""
    text = " ".join(_LINK.sub(r"\1", text).split())
    if len(text) > limit:
        text = text[:limit].rsplit(" ", 1)[0].rstrip(",;:(") + " ..."
    parts = text.split("`")  # the odd parts are code spans, which keep their `<` as it is
    text = "`".join(p.replace("<", "&lt;") if i % 2 == 0 else p for i, p in enumerate(parts))
    return text.replace("|", "&#124;")


HEADER = """# Mistakes by area

<!-- Built from the rules of the topic sections and the old lesson files by `gds lessons <area>` and
`python .github/scripts/mistakes.py render`, which print it: edit those, not this page. It is not a file in the
repository. -->

Read the sections of your task's areas before you start: each line is a rule we learned the hard way, and the check
that keeps it. Rules live in the topic sections (docs/studio/rules.md; `gds learn <words>` finds the closest); the
old lesson files of docs/lessons/ follow until #770 moves them. `gds issue start` records an issue's areas from its
labels and the hooks put these sections into the agent's context.
"""


def build(root: Path) -> str:
    """The text of the glossary for the rules and the old lesson files of a kit checkout."""
    areas = Areas.load(root / AREAS_FILE)
    sections: dict[str, list[tuple[str, str, str]]] = {a: [] for a in areas.names}
    for s in sections_in(root):
        for rule in s.rules():
            parts = rule_parts(rule) or {"Approach": rule, "Watch out for": ""}
            link = f"[section](../{s.page}#{s.anchor})"
            for area in areas.for_page(s.page, rule):
                sections.setdefault(area, []).append(
                    (brief(parts["Approach"], 170), brief(parts["Watch out for"] or s.ref, 260), link)
                )
    for lesson in reversed(lessons_in(root)):  # newest first
        link = f"[lesson](../lessons/{lesson.path.name})"
        for area in lesson.areas or [GENERAL]:
            sections.setdefault(area, []).append(
                (brief(lesson.title, 150), brief(lesson.fix or lesson.cause or "see the lesson", 260), link)
            )
    out = [HEADER]
    for area, description in areas.names.items():
        items = sections.get(area, [])
        out.append(f"## {area}\n\n{description} ({len(items)})\n")
        if items:
            out.append("| Mistake | Check | Source |\n| --- | --- | --- |")
            out += [f"| {m} | {c} | {s} |" for m, c, s in items]
            out.append("")
    return "\n".join(out).rstrip("\n") + "\n"


def _plain(cell: str) -> str:
    return cell.replace("\\|", "|").replace("&#124;", "|").replace("&lt;", "<")


def section(glossary: str, area: str) -> list[tuple[str, str]]:
    """The (mistake, check) pairs of one area in the glossary's text."""
    items, on = [], False
    for line in glossary.replace("\r\n", "\n").splitlines():
        if line.startswith("## "):
            on = line[3:].strip() == area
        elif on and line.startswith("| ") and not line.startswith(("| Mistake", "| ---")):
            parts = cells(line)
            if len(parts) == 3:
                items.append((_plain(parts[0]), _plain(parts[1])))
    return items


def checks_text(glossary: str, wanted: list[str], per_area: int = 12) -> str:
    """The checks of some areas as plain text for an agent's context: the first `per_area` of each (the rules of the
    sections, then the newest old lessons)."""
    lines = []
    for area in wanted:
        items = section(glossary, area)[:per_area]
        if items:
            lines.append(f"[{area}]")
            lines += [f"- {mistake}: {check}" for mistake, check in items]
    return "\n".join(lines)
