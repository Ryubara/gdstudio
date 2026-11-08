"""The docs site: the Zensical pin, the topic folders and the redirects of moved pages (docs/studio/docs-site.md)."""

from __future__ import annotations

import importlib.util
import re
from pathlib import Path

import yaml

KIT = Path(__file__).resolve().parents[2]
DOCS = KIT / "docs"
TOPICS = ["gamedev", "engines", "tools", "studio", "games"]


def load_redirects():
    spec = importlib.util.spec_from_file_location("site_redirects", KIT / ".github" / "scripts" / "site_redirects.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def test_zensical_is_pinned_by_exact_version_with_a_hash_for_every_package():
    direct = [
        ln for ln in (KIT / "requirements-docs.in").read_text(encoding="utf-8").splitlines() if ln and ln[0] != "#"
    ]
    assert len(direct) == 1 and re.fullmatch(r"zensical==\d+\.\d+\.\d+", direct[0]), direct
    text = (KIT / "requirements-docs.txt").read_text(encoding="utf-8")
    entries = re.split(r"\n(?=[a-z])", text[text.index("\n", text.index("uv pip compile")) + 1 :].strip())
    names = {}
    for entry in entries:
        head = entry.split("\\", 1)[0].strip()
        assert re.fullmatch(r"[a-z0-9_.-]+==[\w.]+( ; .+)?", head), head
        assert "--hash=sha256:" in entry, f"{head} has no hash"
        name, version = head.split(" ; ")[0].split("==")
        names[name] = version
    assert f"zensical=={names['zensical']}" == direct[0]


# Plugins Zensical 0.1.0 implements itself, reading their files without running any plugin code.
NATIVE_PLUGINS = {"awesome-nav"}


def site_config() -> dict:
    return yaml.safe_load((KIT / "mkdocs.yml").read_text(encoding="utf-8"))


def test_the_config_has_no_hooks_or_plugins_that_zensical_would_skip():
    """Zensical reads mkdocs.yml but runs no MkDocs hooks and no plugin code: a check put there would never run.
    Only the plugins it implements natively may be named."""
    config = site_config()
    assert "hooks" not in config and config["strict"] is True
    assert set(config.get("plugins", [])) <= NATIVE_PLUGINS


def test_the_sidebar_folds_by_tab():
    """Topics are header tabs and a tab's sections fold open and shut (docs/studio/docs-site.md#nav):
    navigation.sections would open every group at once, the way #768 listed 970 lessons in one column."""
    config = site_config()
    features = config["theme"]["features"]
    assert {"navigation.tabs", "navigation.indexes", "navigation.prune"} <= set(features)
    assert "navigation.sections" not in features and "navigation.expand" not in features
    assert "not_in_nav" not in config  # the old lessons folder is gone (gdstudio #770)
    assert not (DOCS / "lessons").exists()


def nav_entries(folder: Path) -> list[str]:
    nav = yaml.safe_load((folder / ".nav.yml").read_text(encoding="utf-8"))["nav"]
    return [next(iter(e.values())) if isinstance(e, dict) else e for e in nav]


def test_the_nav_order_lists_every_topic_and_every_engine_and_tool():
    """A folder a .nav.yml leaves out drops out of the sidebar without a warning; a listed one that is gone fails
    the build. The top lists every topic; engines/ and tools/ list each of their folders."""
    assert nav_entries(DOCS) == ["index.md", *TOPICS]
    for parent in ("engines", "tools"):
        folders = sorted(p.name for p in (DOCS / parent).iterdir() if p.is_dir())
        assert sorted(nav_entries(DOCS / parent)) == folders, f"docs/{parent}/.nav.yml must list every folder"


def test_the_docs_are_laid_out_by_topic_with_an_index_in_every_folder():
    top = sorted(p.name for p in DOCS.iterdir() if p.is_dir())
    assert top == sorted(TOPICS), "a new top-level folder belongs on docs/studio/docs-site.md#folders first"
    assert sorted(p.name for p in DOCS.glob("*.md")) == ["index.md"]
    folders = [p for p in DOCS.rglob("*") if p.is_dir()]
    assert [p for p in folders if not (p / "index.md").is_file()] == []
    home = (DOCS / "index.md").read_text(encoding="utf-8")
    assert all(f"({t}/index.md)" in home for t in TOPICS)


def test_an_engine_or_tool_folder_is_never_an_empty_stub():
    for parent in ("engines", "tools"):
        for folder in (p for p in (DOCS / parent).iterdir() if p.is_dir()):
            assert len(list(folder.glob("*.md"))) > 1, f"{folder.relative_to(KIT)} holds only its index"


def test_every_moved_page_has_a_new_page_and_its_old_path_is_free():
    moves = load_redirects().pages()
    assert len(moves) >= 70
    for old, new in moves.items():
        assert (DOCS / new).is_file(), f"{old} -> {new}: no such page"
        assert not (DOCS / old).exists(), f"{old} is a page again: remove it from the map"


def test_the_redirect_pages_send_the_reader_on_and_keep_the_anchor(tmp_path):
    redirects = load_redirects()
    assert redirects.address("godot/no-focus.md") == "godot/no-focus/"
    assert redirects.address("godot/index.md") == "godot/"
    moves = {"godot/no-focus.md": "engines/godot/no-focus.md", "godot/index.md": "engines/godot/index.md"}
    for new in ("engines/godot/no-focus/", "engines/godot/"):
        (tmp_path / new).mkdir(parents=True, exist_ok=True)
        (tmp_path / new / "index.html").write_text("page", encoding="utf-8")
    assert redirects.write(tmp_path, moves) == []
    page = (tmp_path / "godot" / "no-focus" / "index.html").read_text(encoding="utf-8")
    assert 'href="../../engines/godot/no-focus/"' in page and "location.hash" in page
    assert 'url=../engines/godot/"' in (tmp_path / "godot" / "index.html").read_text(encoding="utf-8")


def test_a_redirect_to_a_page_the_build_lacks_fails_and_writes_nothing(tmp_path):
    redirects = load_redirects()
    (tmp_path / "hooks").mkdir()
    (tmp_path / "hooks" / "index.html").write_text("page", encoding="utf-8")
    problems = redirects.write(tmp_path, {"hooks.md": "studio/hooks.md"})
    assert any("not in the build" in p for p in problems)
    assert any("a page of the site again" in p for p in problems)
    assert (tmp_path / "hooks" / "index.html").read_text(encoding="utf-8") == "page"
