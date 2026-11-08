"""Write a redirect page at every old address of the docs site (docs/studio/docs-site.md#moved).

    python .github/scripts/site_redirects.py [SITE]   after `zensical build`; SITE defaults to `site`

Zensical runs no MkDocs plugins, so there is no redirects plugin: this script reads `.github/site-redirects.toml` (old
page -> new page, by source path under docs/) and writes `<old address>/index.html` into the built site, which sends
the reader on to the new address, keeping the `#anchor`. It fails when a new page is missing from the build or an old
address is a real page again, so a later move that forgets the map, or reuses an old name, is caught. Standard library
only.
"""

from __future__ import annotations

import html
import posixpath
import sys
import tomllib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
MAP = ROOT / ".github" / "site-redirects.toml"

PAGE = """<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<title>Moved: {title}</title>
<link rel="canonical" href="{href}">
<meta name="robots" content="noindex">
<meta http-equiv="refresh" content="0; url={href}">
<script>location.replace({js} + location.hash)</script>
</head>
<body><p>This page moved to <a href="{href}">{title}</a>.</p></body>
</html>
"""


def address(src: str) -> str:
    """The folder a page is served from with directory URLs: `a/b.md` -> `a/b/`, `a/index.md` -> `a/`."""
    path = src.removesuffix(".md")
    if path == "index" or path.endswith("/index"):
        path = path.removesuffix("index")
    else:
        path += "/"
    return path


def pages(map_file: Path = MAP) -> dict[str, str]:
    return tomllib.loads(map_file.read_text(encoding="utf-8"))["pages"]


def write(site: Path, moves: dict[str, str]) -> list[str]:
    """Write the redirect pages; return the problems instead when there are any (nothing is written then)."""
    problems = []
    plan = {}
    for old, new in moves.items():
        old_dir, new_dir = address(old), address(new)
        if not (site / new_dir / "index.html").is_file():
            problems.append(f"{old} -> {new}: the new page is not in the build")
        if (site / old_dir / "index.html").is_file():
            problems.append(f"{old}: its old address is a page of the site again (remove it from the map)")
        href = posixpath.relpath(new_dir or ".", old_dir.rstrip("/") or ".").rstrip("/") + "/"
        plan[site / old_dir / "index.html"] = PAGE.format(
            title=html.escape(new_dir or "home"), href=html.escape(href), js=repr(href)
        )
    if problems:
        return problems
    for target, text in plan.items():
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(text, encoding="utf-8", newline="\n")
    return []


def main(argv: list[str]) -> int:
    site = Path(argv[0]) if argv else ROOT / "site"
    moves = pages()
    problems = write(site, moves)
    if problems:
        print("\n".join(problems), file=sys.stderr)
        return 1
    print(f"{len(moves)} redirect page(s) written into {site}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
