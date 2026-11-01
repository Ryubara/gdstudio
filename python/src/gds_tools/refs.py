"""`gds refs fetch <url>`: bring a third-party reference into <workspace>/refs/ with its licence (docs/refs.md).

Poly Pizza model and bundle links are understood (`/m/<id>`, `/bundle/<name>-<id>`). Each model lands in
`refs/polypizza/<id>/` (or a bundle's `refs/polypizza/bundles/<id>/models/`) with `meta.json` (the API's answer:
title, creator, licence, attribution, triangle count) and an `index.json` for a bundle. Files in refs/ are never
committed; an asset that later goes into a game gets a licence entry built from this metadata.

The API key comes from the environment (`POLY_PIZZA_API_KEY`) and is never printed.
"""

from __future__ import annotations

import json
import os
import re
import urllib.request
from collections.abc import Callable
from dataclasses import dataclass
from pathlib import Path

API = "https://api.poly.pizza/v1.1"
KEY_ENV = "POLY_PIZZA_API_KEY"
USER_AGENT = "gdstudio-refs/0.1"

Fetch = Callable[[str, dict[str, str]], bytes]


class RefsError(Exception):
    """A link that is not understood, a missing key, or an API failure."""


@dataclass(frozen=True)
class Link:
    """What a link points at: a single model or a bundle (a list of models)."""

    kind: str  # "model" or "bundle"
    ident: str


def parse_link(url: str) -> Link:
    """The model or bundle a poly.pizza link names; RefsError for anything else."""
    model = re.match(r"^https?://(?:www\.)?poly\.pizza/m/([A-Za-z0-9_-]+)/?$", url.strip())
    if model:
        return Link("model", model.group(1))
    bundle = re.match(r"^https?://(?:www\.)?poly\.pizza/bundle/(?:[^/]*-)?([A-Za-z0-9_]+)/?$", url.strip())
    if bundle:
        return Link("bundle", bundle.group(1))
    raise RefsError(f"not a poly.pizza model or bundle link: {url}")


def http_get(url: str, headers: dict[str, str]) -> bytes:
    """GET a URL and return its body."""
    request = urllib.request.Request(url, headers={"User-Agent": USER_AGENT, **headers})
    with urllib.request.urlopen(request, timeout=60) as response:
        return response.read()


def _api(path: str, fetch: Fetch) -> dict:
    key = os.environ.get(KEY_ENV)
    if not key:
        raise RefsError(f"{KEY_ENV} is not set (a free key from poly.pizza; set it with setx, never in a file)")
    try:
        return json.loads(fetch(f"{API}{path}", {"x-auth-token": key}))
    except OSError as error:
        raise RefsError(f"Poly Pizza API {path}: {error}") from error


def _save_model(meta: dict, folder: Path, fetch: Fetch, log: Callable[[str], None]) -> Path:
    """Download one model's glTF (skipped when present) and write its meta.json; returns the model file."""
    folder.mkdir(parents=True, exist_ok=True)
    target = folder / "model.glb"
    if not target.exists():
        target.write_bytes(fetch(meta["Download"], {}))
    (folder / "meta.json").write_text(json.dumps(meta, indent=1), encoding="utf-8")
    log(f"  {meta['ID']}  {meta.get('Title', '')}  {meta.get('Tri Count', '?')} tris  {meta.get('Licence', '?')}")
    return target


def fetch_link(url: str, refs: Path, fetch: Fetch = http_get, log: Callable[[str], None] = print) -> Path:
    """Fetch what `url` names into `refs`; returns the folder written."""
    link = parse_link(url)
    if link.kind == "model":
        meta = _api(f"/model/{link.ident}", fetch)
        folder = refs / "polypizza" / link.ident
        _save_model(meta, folder, fetch, log)
        return folder
    data = _api(f"/list/{link.ident}", fetch)
    folder = refs / "polypizza" / "bundles" / link.ident
    folder.mkdir(parents=True, exist_ok=True)
    (folder / "bundle.json").write_text(json.dumps(data, indent=1), encoding="utf-8")
    index = []
    for meta in data.get("Models", []):
        model_dir = folder / "models" / meta["ID"]
        _save_model(meta, model_dir, fetch, log)
        index.append(
            {
                k: meta.get(v)
                for k, v in (
                    ("id", "ID"),
                    ("title", "Title"),
                    ("tris", "Tri Count"),
                    ("animated", "Animated"),
                    ("category", "Category"),
                    ("licence", "Licence"),
                    ("attribution", "Attribution"),
                )
            }
        )
    (folder / "index.json").write_text(json.dumps(index, indent=1), encoding="utf-8")
    log(f"{len(index)} models from {data.get('Name', link.ident)}")
    return folder


def licence_entry(meta: dict) -> str:
    """A TOML licence-manifest entry for a model, from its meta.json."""

    def q(text: object) -> str:
        return json.dumps(str(text or ""))

    return (
        "\n".join(
            [
                f"[assets.{meta['ID']}]",
                f"title = {q(meta.get('Title'))}",
                f"author = {q((meta.get('Creator') or {}).get('Username'))}",
                f"licence = {q(meta.get('Licence'))}",
                f"source = {q('https://poly.pizza/m/' + meta['ID'])}",
                f"attribution = {q(meta.get('Attribution'))}",
            ]
        )
        + "\n"
    )
