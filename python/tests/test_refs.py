"""`gds refs fetch`: link parsing, model and bundle downloads, the missing-key error and licence entries, with the
network replaced by a fake."""

import json

import pytest

from gds_tools import refs

MODEL = {
    "ID": "VlXjG0N8Eg",
    "Title": "Zombie",
    "Licence": "CC0 1.0",
    "Tri Count": 7570,
    "Download": "https://static.poly.pizza/z.glb",
    "Creator": {"Username": "Quaternius"},
    "Attribution": '"Zombie" by Quaternius',
}


def fake(responses):
    calls = []

    def fetch(url, headers):
        calls.append((url, headers))
        return responses[url]

    fetch.calls = calls
    return fetch


@pytest.mark.parametrize(
    ("url", "kind", "ident"),
    [
        ("https://poly.pizza/m/VlXjG0N8Eg", "model", "VlXjG0N8Eg"),
        ("https://poly.pizza/bundle/Toon-Shooter-Game-Kit-qraiSXoAru", "bundle", "qraiSXoAru"),
    ],
)
def test_parse_link(url, kind, ident):
    assert refs.parse_link(url) == refs.Link(kind, ident)


def test_parse_link_refuses_other_sites():
    with pytest.raises(refs.RefsError):
        refs.parse_link("https://example.com/m/abc")


def test_model_fetch_writes_file_and_meta(tmp_path, monkeypatch):
    monkeypatch.setenv(refs.KEY_ENV, "k")
    fetch = fake({f"{refs.API}/model/VlXjG0N8Eg": json.dumps(MODEL).encode(), MODEL["Download"]: b"glb"})
    folder = refs.fetch_link("https://poly.pizza/m/VlXjG0N8Eg", tmp_path, fetch, lambda _: None)
    assert (folder / "model.glb").read_bytes() == b"glb"
    assert json.loads((folder / "meta.json").read_text())["Licence"] == "CC0 1.0"
    assert fetch.calls[0][1] == {"x-auth-token": "k"}


def test_bundle_fetch_writes_index(tmp_path, monkeypatch):
    monkeypatch.setenv(refs.KEY_ENV, "k")
    bundle = {"Name": "Kit", "Models": [MODEL]}
    fetch = fake({f"{refs.API}/list/qraiSXoAru": json.dumps(bundle).encode(), MODEL["Download"]: b"glb"})
    folder = refs.fetch_link("https://poly.pizza/bundle/Kit-qraiSXoAru", tmp_path, fetch, lambda _: None)
    assert json.loads((folder / "index.json").read_text())[0]["title"] == "Zombie"
    assert (folder / "models" / "VlXjG0N8Eg" / "model.glb").exists()


def test_missing_key_is_a_clear_error(tmp_path, monkeypatch):
    monkeypatch.delenv(refs.KEY_ENV, raising=False)
    with pytest.raises(refs.RefsError, match="POLY_PIZZA_API_KEY"):
        refs.fetch_link("https://poly.pizza/m/VlXjG0N8Eg", tmp_path, fake({}), lambda _: None)


def test_licence_entry():
    entry = refs.licence_entry(MODEL)
    assert entry.startswith("[assets.VlXjG0N8Eg]") and 'licence = "CC0 1.0"' in entry and "Quaternius" in entry
