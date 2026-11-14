"""Topic sections, the entries that record what was learned, the checks of their format, `gds learn`, and the
sections proposed for an issue (`gds brief`).

What was learned goes into the topic page agents read for that task, as a short entry in the page's own voice
(docs/studio/rules.md): `- **Approach:** ... **Watch out for:** ... **Seen:** ...`, in a `##`/`###` section with an
explicit `{#anchor}`, named elsewhere as `page.md#anchor`. There are no lesson pages. This module reads the sections
and entries of the docs, finds the ones closest to some words (`gds learn`) or to an issue (`propose`, which
`gds brief` prints as `Read:` lines for a task agent's prompt), and checks the format (`problems`, and
`base_problems` against the base of a pull request): no new file under the old `docs/lessons/` folder, no page past
its size, no new section without a reason line, no malformed entry or anchor, and no corrections-log row that quotes
the maintainer or links no section.

The old lesson files (`docs/lessons/<date>-<slug>.md`) stay readable for `gds learn --old` until gdstudio #770 empties
the folder. There are no lesson categories: what an agent reads is named by section. Standard library only: the hooks
load this file by path.
"""

from __future__ import annotations

import math
import posixpath
import re
import subprocess
import unicodedata
from dataclasses import dataclass
from itertools import pairwise
from pathlib import Path

DOCS = Path("docs")
CORRECTIONS = DOCS / "studio" / "maintainer-corrections.md"
#: The log's rows, one page per kind, since the page reached the size limit (gdstudio #1115).
CORRECTIONS_LOG = DOCS / "studio" / "corrections-log"
LESSONS = DOCS / "lessons"
RULES_DOC = DOCS / "studio" / "rules.md"

#: `learning` of .github/conventions.yml (a test keeps them equal).
MAX_PAGE_KB = 50
MAX_RULE_CHARS = 900
RULE_PARTS = ("Approach:", "Watch out for:", "Seen:")
REASON_LINE = "<!-- new section:"
#: The folders under docs/ whose every `##`/`###` heading has an explicit `{#anchor}` (rules.md#anchors), so a
#: `Read:` line or a link can name any of their sections.
ANCHORED_FOLDERS = ("studio", "engines", "tools", "gamedev")

_LINK = re.compile(r"\[([^\]]*)\]\([^)]*\)")
_HEADING = re.compile(r"^(#{1,6})\s+(.+?)\s*#*\s*$")
_ATTRS = re.compile(r"\s*\{:?([^{}]*)\}\s*$")
_ANCHOR = re.compile(r"[a-z0-9]+(?:-[a-z0-9]+)*")
_FENCE = re.compile(r"^\s*(```|~~~)")
_RULE_START = re.compile(r"^- \*\*Approach:\*\*")
_OLD_RULE = re.compile(r"^- \*\*Rule:\*\*")
_REF = re.compile(r"((?:[\w.-]+/)*[\w.-]+\.md)#([A-Za-z0-9_-]+)")
_SEEN_SOURCE = re.compile(r"#\d+|20\d\d-\d\d-\d\d|github\.com/")


class LessonsError(Exception):
    """The lessons or the glossary are inconsistent."""


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


#: A pointer section's own text (without its comments) is at most this long: a note that the section moved, not a
#: section with text of its own.
POINTER_CHARS = 400
_MD_LINK = re.compile(r"\[[^\]]*\]\(\s*((?:[\w.-]+/)*[\w.-]+\.md)#([A-Za-z0-9_-]+)\s*\)")
_MOVED_NOTE = re.compile(r"<!--\s*moved\b", re.IGNORECASE)


def moved_to(section: Section) -> tuple[str, str] | None:
    """(page under docs/, anchor) of the section a pointer left by a split sends its reader to, None for a section with
    text of its own. A pointer is a short note (`POINTER_CHARS`) that links to a section on another page with its own
    anchor, or, under a `<!-- moved: ... -->` note or starting "Moved", to one section (gdstudio #1471:
    `own-animation.md#audit-gaits` says "Moved to [The gaits](library-clip-audit.md#audit-gaits)")."""
    prose = re.sub(r"<!--.*?-->", "", section.body, flags=re.DOTALL).strip()
    if not prose or len(prose) > POINTER_CHARS:
        return None
    links: list[tuple[str, str]] = []
    for found in _MD_LINK.finditer(prose):
        page = posixpath.normpath(posixpath.join(posixpath.dirname(section.page), found.group(1)))
        if not page.startswith("../") and page != section.page and (page, found.group(2)) not in links:
            links.append((page, found.group(2)))
    same = [link for link in links if link[1] == section.anchor]
    if same:
        return same[0]
    marked = prose.lower().startswith("moved") or _MOVED_NOTE.search(section.body)
    return links[0] if marked and len(links) == 1 else None


def follow(section: Section, by_ref: dict[str, Section]) -> Section:
    """The section a pointer leads to through every hop (`moved_to`), the section itself when it is not a pointer or
    its target is not in `by_ref`."""
    seen = {section.ref}
    while (target := moved_to(section)) and (ref := f"{target[0]}#{target[1]}") in by_ref and ref not in seen:
        section = by_ref[ref]
        seen.add(ref)
    return section


def moved_home(page: str, anchor: str, sections: list[Section]) -> Section | None:
    """The section that holds `anchor` now that `page` no longer has it (a split whose pointer was removed later): the
    only other section with that anchor, or the only one in the page's folder; None when no single one fits."""
    found = [s for s in sections if s.anchor == anchor and s.page != page and not moved_to(s)]
    if len(found) > 1:
        found = [s for s in found if posixpath.dirname(s.page) == posixpath.dirname(page)]
    return found[0] if len(found) == 1 else None


def page_problems(page: str, text: str) -> list[str]:
    """The format problems of one topic page: its size, its anchors (every `##`/`###` heading of a page under
    ANCHORED_FOLDERS has an explicit one) and its rules."""
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
        if s.level in (2, 3) and not s.explicit and page.split("/", 1)[0] in ANCHORED_FOLDERS:
            found.append(
                f"docs/{page}:{s.line}: the heading '{s.title}' has no explicit {{#anchor}}; add "
                f"{{#{s.anchor}}}, the anchor it already has ({RULES_DOC.as_posix()}#anchors)"
            )
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


def problems(root: Path) -> list[str]:
    """Everything a checkout alone can show is wrong: topic pages past their size or with a malformed anchor or rule,
    and corrections-log rows that quote the maintainer or link no section."""
    found = []
    for path in topic_pages(root):
        found += page_problems(path.relative_to(root / DOCS).as_posix(), path.read_text(encoding="utf-8"))
    for path in corrections_pages(root):
        text = path.read_text(encoding="utf-8")
        page = path.relative_to(root).as_posix()
        found += quoted_rows(text, page) + unlinked_rows(text, page)
    return found


def corrections_pages(root: Path) -> list[Path]:
    """The corrections log: the old page and every page of its folder, sorted."""
    pages = [root / CORRECTIONS] if (root / CORRECTIONS).exists() else []
    folder = root / CORRECTIONS_LOG
    return pages + (sorted(folder.rglob("*.md")) if folder.is_dir() else [])


def is_corrections_page(page: str) -> bool:
    """True for a page under docs/ (`studio/maintainer-corrections.md`) that is the corrections log or one of its
    pages: a log, not where a rule lives."""
    page = page.split("docs/", 1)[1] if "docs/" in page else page
    log = CORRECTIONS_LOG.relative_to(DOCS).as_posix() + "/"
    return page == CORRECTIONS.relative_to(DOCS).as_posix() or page.startswith(log)


def _new_lesson_message(name: str) -> str:
    return (
        f"docs/lessons/{name}: no new file goes in the old lessons folder (emptied by gdstudio #770); write the rule "
        f"into the topic section it belongs to (`gds learn <words>` finds it; {RULES_DOC.as_posix()})"
    )


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


def quoted_rows(text: str, page: str = CORRECTIONS.as_posix()) -> list[str]:
    """Rows of the corrections log with a cell that starts with a quotation mark. A row says what the maintainer
    pointed out in our words, with its source; the maintainer's prompts are never quoted in a public repository
    (gdstudio #780)."""
    found = []
    for number, line in _table_rows(text):
        quoted = next((c for c in cells(line) if c[:1] in _QUOTES), None)
        if quoted is not None:
            found.append(
                f"{page}:{number}: the row quotes the maintainer ({quoted[:40]}...); "
                "say what was pointed out in our words, with its source, never the prompt"
            )
    return found


def unlinked_rows(text: str, page: str = CORRECTIONS.as_posix()) -> list[str]:
    """Rows of the corrections log whose last cell links no section (`page.md#anchor`): the rule lives there."""
    return [
        f"{page}:{number}: the row links no section; its last cell names where the rule lives "
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
    it under its `#` title; an existing page under each new `##`/`###` heading whose parent heading is not new too. A
    heading is new when the old page has neither its anchor nor its words: rewording keeps the anchor, and an anchor
    given to an old heading keeps the words."""
    lines = new.replace("\r\n", "\n").split("\n")
    sections = parse_sections(page, new)
    if old is None:
        wanted = [s for s in sections if s.level == 1][:1]
    else:
        before = parse_sections(page, old)
        known, titles = {s.anchor for s in before}, {s.title for s in before}
        wanted, parents = [], {}
        for s in sections:
            is_new = s.anchor not in known and s.title not in titles  # a new anchor on old words is not a new section
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
    moved_from: str = ""  # the pointer's `page.md#anchor` when the section was reached through one


#: How much more a section scores in `gds learn` for holding the query's words side by side as the query has them
#: ("fails in a full run", "passes alone"): its score grows by this times the share of the query's adjacent word pairs
#: it has. Common words are not terms, so "full run" is a pair in "fails in a full run" too. Without it a long section
#: that has every word scattered outranked the one that says the phrase (gdstudio #1471: `ui-input-tests.md#leaks`
#: fell from the top three as main's pages grew).
PAIR_BONUS = 1.0


def _pairs(*texts: list[str]) -> set[tuple[str, str]]:
    """The adjacent term pairs of each term list (pairs never span two lists)."""
    return {pair for words in texts for pair in pairwise(words)}


def _rank(query: list[str], docs: list[tuple[object, list[str], list[str], list[str]]]) -> list[tuple[float, object]]:
    """BM25 over (item, title terms, path terms, body terms): a title word counts 4, a path word 2, a body word 1, the
    score is scaled by the share of the query's terms the item has, and raised by the share of the query's adjacent
    pairs it has side by side (`PAIR_BONUS`)."""
    wanted = list(dict.fromkeys(query))
    if not wanted or not docs:
        return []
    asked = _pairs(query) - {(w, w) for w in wanted}
    counted = []
    for item, title, path, body in docs:
        tf: dict[str, float] = {}
        for weight, words in ((4.0, title), (2.0, path), (1.0, body)):
            for w in words:
                tf[w] = tf.get(w, 0.0) + weight
        near = len(asked & _pairs(title, body)) / len(asked) if asked else 0.0
        counted.append((item, tf, len(title) * 4 + len(path) * 2 + len(body), near))
    total = len(counted)
    average = sum(n for _, _, n, _ in counted) / total or 1.0
    df = {t: sum(1 for _, tf, _, _ in counted if t in tf) for t in wanted}
    out = []
    for item, tf, length, near in counted:
        hits = [t for t in wanted if t in tf]
        if not hits:
            continue
        score = 0.0
        for t in hits:
            idf = math.log(1 + (total - df[t] + 0.5) / (df[t] + 0.5))
            score += idf * tf[t] * 2.2 / (tf[t] + 1.2 * (0.25 + 0.75 * length / average))
        out.append((score * len(hits) / len(wanted) * (1 + PAIR_BONUS * near), item))
    return sorted(out, key=lambda pair: -pair[0])


def resolve_ref(
    page: str, anchor: str, sections: list[Section], by_ref: dict[str, Section]
) -> tuple[Section, str] | None:
    """The section a named `page.md#anchor` leads to among `by_ref`, and the ref it moved from ("" when it did not): a
    pointer is followed (`follow`), and an anchor its page no longer has goes to the section that has it now
    (`moved_home`). None when the ref names a section left out of `by_ref` or nothing that can be found."""
    ref = f"{page}#{anchor}"
    if ref in by_ref:
        found = by_ref[ref]
    elif any(s.ref == ref for s in sections):
        return None
    elif (home := moved_home(page, anchor, list(by_ref.values()))) is not None:
        found = home
    else:
        return None
    target = follow(found, by_ref)
    return target, ("" if target.ref == ref else ref)


def learn(root: Path, words: str, limit: int = 5) -> list[Match]:
    """The `limit` sections of the topic pages closest to `words`, best first: a section the words name as
    `page.md#anchor` first, and a pointer a split left (`moved_to`) replaced by the section it leads to."""
    query = terms(words)
    skip = {RULES_DOC.relative_to(DOCS).as_posix()}  # the format; the log is left out too
    every = sections_in(root)
    sections = [s for s in every if s.page not in skip and not is_corrections_page(s.page)]
    by_ref = {s.ref: s for s in sections}
    ranked = _rank(query, [(s, terms(s.title), terms(s.page.replace(".md", "")), terms(s.body)) for s in sections])
    top = ranked[0][0] if ranked else 0.0
    found: list[tuple[float, Section, str]] = []
    for page, anchor in refs_in(words):
        if (named := resolve_ref(page, anchor, every, by_ref)) is not None:
            found.append((top, *named))
    for score, s in ranked:
        target = follow(s, by_ref)  # type: ignore[arg-type]
        found.append((score, target, "" if target is s else s.ref))  # type: ignore[union-attr]
    out: list[Match] = []
    for score, s, moved in found:
        if len(out) < limit and all(m.section and m.section.ref != s.ref for m in out):
            out.append(Match(score, section=s, moved_from=moved))
    return out


def _first_words(text: str, limit: int) -> str:
    text = " ".join(_LINK.sub(r"\1", text).split())
    return text if len(text) <= limit else text[:limit].rsplit(" ", 1)[0] + " ..."


def learn_text(root: Path, words: str, limit: int = 5, rules_per: int = 4) -> str:
    """What `gds learn` prints: each close section as `page.md#anchor` with its rules (or its first words when it has
    none)."""
    matches = [m for m in learn(root, words, limit) if m.section]
    if not matches:
        return f"No section mentions {words!r}. Make a new one where it belongs ({RULES_DOC.as_posix()}#section)."
    lines = [
        f"The sections closest to {words!r}, best first. Update one of them (add to an entry's Seen, sharpen it, or "
        f"add an entry) before you make a new section ({RULES_DOC.as_posix()}):"
    ]
    for number, match in enumerate(matches, 1):
        s = match.section
        assert s is not None
        rules = s.rules()
        moved = f" (moved from {match.moved_from})" if match.moved_from else ""
        lines += ["", f"{number}. {s.ref}  {s.title}  (docs/{s.page}:{s.line}, {len(rules)} entr(y/ies)){moved}"]
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
    return "\n".join(lines)


# --------------------------------------------------------------------------------------------------------------------
# `gds brief`: the sections a task agent reads before it starts, proposed from its issue
# --------------------------------------------------------------------------------------------------------------------

# A path an issue names: a file with a known extension (`tools.toml`, `.claude/hooks/dispatch.py`) or a folder of two
# parts or more that ends in a slash (`docs/lessons/`; a bare `design/` matches too much prose). Words that merely
# contain a dot (`e.g.`, `v1.2`) are not paths.
_PATH = re.compile(
    r"(?<![\w/.#-])((?:\.?[\w-]+/)*\.?[\w-]+\.(?:py|md|toml|ya?ml|json|gd|tscn|tres|gdshader|ps1|sh|cfg|blend|glb)"
    r"(?![\w-])|(?:\.?[\w-]+/){2,}(?![\w.-]))"
)
#: How much each source of words counts in the query: the issue's title, the words of its area labels, its body.
#: Tuned on the open kit issues of 2026-11-07 (#768, #770, #771, #773, #774): with the body at full weight, the two
#: longest studio sections topped every issue.
TITLE_WEIGHT, LABEL_WEIGHT, BODY_WEIGHT = 3.0, 2.0, 0.3
#: BM25's length normalisation (0.75 is the usual value; more weighs a long section down harder).
LENGTH_B = 0.9
#: At most this many proposed sections come from one page by words alone, so one long page does not take every slot.
PER_PAGE = 2
#: A section whose own text (without its subsections) is shorter than this is a heading over subsections: skipped.
MIN_BODY_CHARS = 80
#: A section found only because it mentions a path the issue names is named when its word score is at least this share
#: of the best section's: a path named in passing (an `Area` line's `game/core/`, a file a section cites as an example)
#: otherwise briefs a section about something else (gdstudio #1133: voice lines for online play, at 0.19). Tuned on
#: 120 kit issues of 2026-11-11: the mentions far from the task scored 0.17 to 0.31, those that fit 0.35 and up.
MENTION_FLOOR = 1 / 3


@dataclass(frozen=True)
class Proposal:
    """One section proposed for a task, and why."""

    section: Section
    why: str

    @property
    def line(self) -> str:
        return f"Read: {self.section.ref}"


def paths_in(text: str) -> list[str]:
    """The file and folder paths a text names, in order, without repeats; URLs and `page.md#anchor` refs are skipped
    (`refs_in` reads a ref)."""
    text = re.sub(r"https?://\S+", " ", text)
    text = _REF.sub(" ", text)
    out: list[str] = []
    for found in _PATH.finditer(text):
        path = found.group(1)
        if path not in out:
            out.append(path)
    return out


def _weighted_rank(
    query: dict[str, float], docs: list[tuple[Section, list[str], list[str], list[str]]]
) -> list[tuple[float, Section]]:
    """BM25 like `_rank`, with each query term weighted (a title word counts more than a body word) and a stronger
    length normalisation (`LENGTH_B`), so a long section that mentions everything does not top every issue."""
    if not query or not docs:
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
    df = {t: sum(1 for _, tf, _ in counted if t in tf) for t in query}
    out = []
    for item, tf, length in counted:
        hits = [t for t in query if t in tf]
        if not hits:
            continue
        score = 0.0
        for t in hits:
            idf = math.log(1 + (total - df[t] + 0.5) / (df[t] + 0.5))
            score += query[t] * idf * tf[t] * 2.2 / (tf[t] + 1.2 * (1 - LENGTH_B + LENGTH_B * length / average))
        out.append((score, item))
    return sorted(out, key=lambda pair: -pair[0])


def _query(title: str, labels: dict[str, str], body: str) -> dict[str, float]:
    """The weighted search terms of an issue: its title (without its `area:` prefix), its area labels (`A-<area>` and
    the label's description) and its body (code blocks and quoted lines left out). A word takes the highest weight of
    the places it appears in."""
    body = re.sub(r"```.*?```", " ", body, flags=re.DOTALL)
    body = "\n".join(ln for ln in body.splitlines() if not ln.lstrip().startswith(">"))
    out: dict[str, float] = {}
    for weight, text in (
        (BODY_WEIGHT, body),
        (LABEL_WEIGHT, " ".join(f"{n[2:]} {d}" for n, d in labels.items() if n.startswith("A-"))),
        (TITLE_WEIGHT, title.split(":", 1)[-1]),
    ):
        for t in terms(text):
            out[t] = max(out.get(t, 0.0), weight)
    return out


def _readable(s: Section) -> bool:
    """A section with text of its own (not a heading over subsections only)."""
    return len(re.sub(r"<!--.*?-->", "", s.body, flags=re.DOTALL).strip()) >= MIN_BODY_CHARS


def propose(
    root: Path,
    title: str,
    body: str = "",
    labels: dict[str, str] | None = None,
    paths: list[str] | None = None,
    limit: int = 6,
) -> list[Proposal]:
    """The sections of the kit's topic pages a task agent reads before it starts, best first, at most `limit`:

    1. every `page.md#anchor` the issue names that exists, or the section it moved to (`resolve_ref`; any section
       proposed that a split left as a pointer is replaced by the one it leads to, gdstudio #1471);
    2. for each path it names (then `paths`, such as a pull request's changed files): a docs page gives its section
       closest to the issue's words, any other path the closest section that mentions it, when its words are not far
       from the issue's (`MENTION_FLOOR`; a pull request's changed files need no such closeness);
    3. the rest by the issue's words (`_query`: title, area labels with their descriptions, body), at most `PER_PAGE`
       from one page.

    The corrections log and the format page (rules.md) are left out, as in `learn`, and so is every heading without an
    explicit `{#anchor}` (a page's `#` title, a heading outside the anchored folders): a `Read:` line names an anchor
    the reader finds written in the page (gdstudio #1193: `ai.md#ai-characters-in-3d-third-person` and
    `index.md#blender`, the slugs of two titles, read as missing to the agents given them)."""
    query = _query(title, labels or {}, body)
    skip = {RULES_DOC.relative_to(DOCS).as_posix()}
    every = sections_in(root)
    sections = [s for s in every if s.explicit and s.page not in skip and not is_corrections_page(s.page)]
    by_ref = {s.ref: s for s in sections}
    docs = [(s, terms(s.title), terms(s.page.replace(".md", "")), terms(s.body)) for s in sections]
    ranked = _weighted_rank(query, docs)
    score = {s.ref: sc for sc, s in ranked}
    out: list[Proposal] = []

    def add(s: Section, why: str, moved: str = "") -> bool:
        """Propose `s`, or the section it points to when a split left it as a pointer (gdstudio #1471)."""
        target = follow(s, by_ref)
        moved = moved or ("" if target is s else s.ref)
        if len(out) >= limit or any(p.section.ref == target.ref for p in out):
            return False
        out.append(Proposal(target, f"{why} (moved from {moved})" if moved else why))
        return True

    for page, anchor in refs_in(f"{title}\n{body}"):
        if (named := resolve_ref(page, anchor, every, by_ref)) is not None:
            add(named[0], "named in the issue", named[1])
    for path in dict.fromkeys([*paths_in(f"{title}\n{body}"), *(paths or [])]):
        page = path.split("docs/", 1)[1] if path.startswith("docs/") else path
        on_page = [s for s in sections if s.page == page and _readable(s)]
        if on_page:
            add(max(on_page, key=lambda s: (score.get(s.ref, 0.0), -s.line)), f"the issue names docs/{page}")
            continue
        needle = path.rstrip("/")
        mentions = [s for s in sections if needle in s.body or needle in s.title]
        name = needle.rsplit("/", 1)[-1]
        if not mentions and "." in name and len(name) >= 8:
            alone = re.compile(rf"(?<![\w.-]){re.escape(name)}(?![\w-])")
            mentions = [s for s in sections if alone.search(s.body)]
        floor = MENTION_FLOOR * ranked[0][0] if ranked and path not in (paths or []) else 0.0
        mentions = [s for s in mentions if score.get(s.ref, 0.0) >= floor]
        if mentions:
            add(max(mentions, key=lambda s: (score.get(s.ref, 0.0), -len(s.body))), f"mentions {path}")
    from_page: dict[str, int] = {}
    for _, s in ranked:
        if len(out) >= limit:
            break
        page = follow(s, by_ref).page
        if _readable(s) and from_page.get(page, 0) < PER_PAGE and add(s, "closest to the issue's words"):
            from_page[page] = from_page.get(page, 0) + 1
    return out


def brief_text(proposals: list[Proposal], why: bool = False) -> str:
    """What `gds brief` prints: one `Read: page.md#anchor` line per section (with `why`, the title and the reason
    after it)."""
    if not why:
        return "\n".join(p.line for p in proposals)
    width = max((len(p.line) for p in proposals), default=0)
    return "\n".join(f"{p.line:{width}}  {p.section.title} ({p.why})" for p in proposals)


def missing_refs(root: Path, text: str) -> list[str]:
    """The `page.md#anchor` refs of a text that name no section of the kit's docs (no such page, or no such anchor on
    it)."""
    return [f"{page}#{anchor}" for page, anchor in refs_in(text) if anchor not in anchors(root / DOCS / page)]
