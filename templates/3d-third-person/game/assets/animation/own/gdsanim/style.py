"""A variant's numbers.

A variant of a clip is the same description with another style file: `styles/style_a.json` is one vision (its
`name` and `vision` are printed on the review sheet), with a section of numbers per clip type (`"idle": {...}`) and
the overlap pass's numbers per part (`"overlap": {"forearm": [lag frames, overshoot]}`). A description declares its
own defaults and what each number means; a style file may only set numbers the description declares, so a typing
mistake in a style file fails the build instead of silently building the default.
"""

import json
from pathlib import Path


class Style:
    """A style file, read over a description's defaults."""

    def __init__(self, path: Path):
        self.path = Path(path)
        self.data = json.loads(self.path.read_text(encoding="utf-8"))
        for key in ("letter", "name", "vision"):
            assert key in self.data, f"{self.path.name} has no `{key}`"
        self.letter = self.data["letter"]
        self.name = self.data["name"]
        self.vision = self.data["vision"]

    def numbers(self, section: str, defaults: dict) -> dict:
        """The numbers of a clip type: the description's `defaults` with the style's own over them."""
        own = self.data.get(section, {})
        unknown = sorted(set(own) - set(defaults))
        assert not unknown, (
            f"{self.path.name}: `{section}` sets {', '.join(unknown)}, which the description does not declare"
        )
        return {**defaults, **own}

    def overlap(self, section: str) -> dict:
        """The overlap numbers per part: the file's `overlap`, with the clip type's own `overlap_<section>` over
        them when it has one (an idle's parts trail further than a sprint's)."""
        return {**self.data.get("overlap", {}), **self.data.get(f"overlap_{section}", {})}

    def notes(self, section: str) -> list:
        """The two lines the review sheet prints for this variant of a clip type."""
        return list(self.data.get("notes", {}).get(section, []))


def load_all(folder: Path) -> list:
    """Every style file of a folder, by letter."""
    styles = [Style(path) for path in sorted(Path(folder).glob("style_*.json"))]
    letters = [style.letter for style in styles]
    assert len(set(letters)) == len(letters), f"two style files share a letter: {letters}"
    return styles
