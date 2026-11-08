"""`gds new game <name> --template <template>`: make a game repository from a template (docs/engines/godot/new-game.md).

A template is a folder of `templates/` with a `template.toml`: its `game/` becomes the game's Godot project and its
`docs/` the game's docs pages. They are copied once, on top of `templates/repo/` (the repository files every game
has: CI, conventions, hooks configuration, docs site, README), with the placeholders below filled in, and from then
on they are the game's own, so `gds sync` never touches them. What `gds sync` does own (agent definitions, the hook
launcher, the commit checker, the message-check hooks) is written by this command too, so a new game starts in sync.

Every new game is MIT, with the kit's owner as the copyright holder, unless `licence` names another SPDX licence
(its text comes from GitHub's licence list). Then the GitHub half (`new_game_github`) creates the repository, public
unless asked otherwise, pushes `main`, applies the settings, waits for the proof and opens the kit pull request that
registers the game: a new game repository made this way, under MIT, is the agent's to make (kit #779). `--local` stops
at the local repository, as the command did before.
"""

from __future__ import annotations

import datetime
import json
import re
import shutil
import subprocess
import tomllib
from collections.abc import Callable
from dataclasses import dataclass
from pathlib import Path

from gds_tools import integrations, issues, sync, worktrees
from gds_tools import new_game_github as github
from gds_tools.manifest import load_tools, load_workspace

#: Folders of `templates/` that are not templates: the files `gds sync` owns, and the repository files every game has.
SYNCED_FOLDER = "game"
REPO_FOLDER = "repo"
#: Kit files copied once, as a game's own afterwards (a game changes them for itself; `gds sync` does not own them).
COPIED_FROM_KIT = (".github/scripts/pr_status.py",)
#: The commit that holds a new game's first state. No trailer: a command wrote it, not an agent.
FIRST_COMMIT = "build: Add the {title} starter"

SLUG = re.compile(r"^[a-z][a-z0-9]*(-[a-z0-9]+)*$")
PLACEHOLDER = re.compile(r"\{(?:GAME_[A-Z]+|KIT_[A-Z]+|TEMPLATE)\}")
DEFAULT_LICENCE = "MIT"
#: The placeholders GitHub's licence texts use for the year and the holder.
LICENCE_YEAR = ("[year]", "[yyyy]")
LICENCE_HOLDER = ("[fullname]", "[name of copyright owner]")
Run = Callable[..., subprocess.CompletedProcess]


class NewGameError(Exception):
    """The game cannot be made as asked; the message says what to change."""


@dataclass(frozen=True)
class Template:
    """One template of `templates/`: its folder and what `template.toml` says about it."""

    name: str
    path: Path
    title: str
    description: str
    default_description: str
    extends: str | None = None


@dataclass(frozen=True)
class Made:
    """What a finished `new_game` left: the repository, whether it was committed, what is left, and the GitHub
    repository with its proof (None with `--local`)."""

    repo: Path
    committed: bool
    todo: list[str]
    published: github.Published | None = None


def available(kit: Path) -> list[str]:
    """The names of the kit's templates."""
    folder = kit / "templates"
    if not folder.is_dir():
        return []
    return sorted(p.name for p in folder.iterdir() if (p / "template.toml").is_file())


def load_template(kit: Path, name: str) -> Template:
    """The template `name`, or a NewGameError listing the ones there are."""
    path = kit / "templates" / name
    if name in {SYNCED_FOLDER, REPO_FOLDER} or not (path / "template.toml").is_file():
        raise NewGameError(f"no template {name!r}; the kit has: {', '.join(available(kit)) or 'none'}")
    data = tomllib.loads((path / "template.toml").read_text(encoding="utf-8"))
    try:
        return Template(
            name=name,
            path=path,
            title=data["title"],
            description=data["description"],
            default_description=data["default_description"],
            extends=data.get("extends"),
        )
    except KeyError as error:
        raise NewGameError(f"templates/{name}/template.toml has no {error.args[0]!r}") from error


def chain(kit: Path, template: Template) -> list[Template]:
    """The templates a game is made from, the base first: a template that `extends` another is that one with its own
    files on top (a later template adds a controller to 3D Blank without copying the level)."""
    found = [template]
    while found[-1].extends:
        base = load_template(kit, found[-1].extends)
        if any(base.name == t.name for t in found):
            raise NewGameError(f"templates {' -> '.join(t.name for t in found)} -> {base.name} extend each other")
        found.append(base)
    return found[::-1]


def check_name(name: str) -> None:
    """A repository name is lowercase words joined by hyphens: it is a folder, a GitHub repository and a CI path."""
    if not SLUG.match(name) or len(name) > 39:
        raise NewGameError(
            f"{name!r} is not a game name: lowercase letters and digits in words joined by hyphens, at most 39 "
            "characters (`my-game`)"
        )


def title_of(name: str) -> str:
    """`my-cool-game` -> `My Cool Game`."""
    return " ".join(word.capitalize() for word in name.split("-"))


def _check_text(label: str, value: str, longest: int) -> str:
    """A title or description is written into project.godot and YAML inside double quotes, so no quote, backslash or
    line break, and into Markdown that keeps lines to 120 characters, so it is not long."""
    if not value.strip() or any(c in value for c in '"\\\n\r') or len(value.strip()) > longest:
        raise NewGameError(
            f"{label} must be one line of at most {longest} characters, without double quotes or backslashes: {value!r}"
        )
    return value.strip()


def kit_repo(kit: Path) -> str:
    """`owner/name` of the kit on GitHub, from its own entry of workspace.toml."""
    entry = load_workspace(kit / "workspace.toml").repos.get("gdstudio")
    found = re.search(r"github\.com[/:]([^/]+/[^/]+?)(?:\.git)?$", entry.url) if entry else None
    if not found:
        raise NewGameError("workspace.toml has no GitHub url for the gdstudio repository")
    return found.group(1)


def substitutions(
    kit: Path, name: str, template: Template, title: str, description: str, holder: str | None = None
) -> dict[str, str]:
    """The words the template files carry as `{NAME}`."""
    owner, repo = kit_repo(kit).split("/")
    return {
        "{GAME_YEAR}": str(datetime.date.today().year),
        "{GAME_COPYRIGHT}": holder or owner,
        "{GAME_TITLE}": title,
        "{GAME_SLUG}": name,
        "{GAME_DESCRIPTION}": description,
        "{TEMPLATE}": template.name,
        "{KIT_REPO}": f"{owner}/{repo}",
        "{KIT_PAGES}": f"{owner.lower()}.github.io/{repo}",
    }


def render(data: bytes, words: dict[str, str]) -> bytes:
    """A file with its placeholders filled in and LF line endings; a file that is not text is returned as it is."""
    try:
        text = data.decode("utf-8")
    except UnicodeDecodeError:
        return data
    text = text.replace("\r\n", "\n")
    for key, value in words.items():
        text = text.replace(key, value)
    return text.encode("utf-8")


def copy_tree(source: Path, target: Path, words: dict[str, str], skip: frozenset[str] = frozenset()) -> list[str]:
    """Copy `source` into `target` with `render`, and return the repository-relative paths written."""
    written = []
    for path in sorted(source.rglob("*")):
        rel = path.relative_to(source)
        if not path.is_file() or rel.as_posix() in skip or ".godot" in rel.parts:
            continue
        data = render(path.read_bytes(), words)
        left = PLACEHOLDER.search(data.decode("utf-8", errors="ignore"))
        if left:
            raise NewGameError(f"{path} has a placeholder the command does not know: {left.group(0)}")
        destination = target / rel
        destination.parent.mkdir(parents=True, exist_ok=True)
        destination.write_bytes(data)
        written.append(rel.as_posix())
    return written


def add_workspace_entry(kit: Path, name: str, remote: str) -> bool:
    """Register the game in the kit's workspace.toml (so `gds workspace init` clones it); False when it is there."""
    path = kit / "workspace.toml"
    text = path.read_text(encoding="utf-8")
    if f"[repos.{name}]" in text:
        return False
    path.write_text(
        f'{text.rstrip()}\n\n[repos.{name}]\nurl = "{remote}"\nrole = "game"\n', encoding="utf-8", newline="\n"
    )
    return True


def licence_text(gh: github.Gh, spdx: str, holder: str) -> str | None:
    """The LICENSE for `spdx`: None for MIT (the template's own file), else GitHub's text with the year and holder."""
    if spdx.upper() == DEFAULT_LICENCE:
        return None
    try:
        body = json.loads(gh(["api", f"licenses/{spdx.lower()}"]) or "{}").get("body", "")
    except (issues.IssueError, ValueError) as error:
        raise NewGameError(f"GitHub has no licence {spdx!r} (an SPDX id such as MIT or Apache-2.0): {error}") from error
    if not body:
        raise NewGameError(f"GitHub's licence {spdx!r} has no text")
    for key in LICENCE_YEAR:
        body = body.replace(key, str(datetime.date.today().year))
    for key in LICENCE_HOLDER:
        body = body.replace(key, holder)
    return body


def _git(run: Run, repo: Path, *args: str) -> subprocess.CompletedProcess:
    return run(["git", "-C", str(repo), *args], capture_output=True, text=True, check=False)


def new_game(
    kit: Path,
    root: Path,
    name: str,
    template_name: str,
    *,
    title: str | None = None,
    description: str | None = None,
    remote: str | None = None,
    licence: str = DEFAULT_LICENCE,
    holder: str | None = None,
    options: github.Options | None = None,
    log: Callable[[str], None] = print,
    run: Run = subprocess.run,
    gh: github.Gh = issues.run_gh,
    **publish_with,
) -> Made:
    """Make `<root>/repos/<name>` from the template: files, licence, `gds sync`, git, the untracked addons, a first
    commit; then, with `options`, everything on GitHub (`new_game_github.publish`).

    `root` is the workspace. A step that needs a program that is not there (git-lfs, pre-commit, an installed Godot
    addon) is skipped with a line saying so, and `Made.todo` carries what is left. `publish_with` goes to `publish`
    (a test's push address, clock and sleep)."""
    check_name(name)
    if options and remote:
        raise NewGameError(
            "--remote records an existing repository and goes with --local; without --local the command creates it"
        )
    template = load_template(kit, template_name)
    parts = chain(kit, template)
    title = _check_text("the title", title or title_of(name), 40)
    description = _check_text("the description", description or template.default_description, 100)
    repo = root / "repos" / name
    if repo.exists():
        raise NewGameError(f"{repo} exists already; pick another name or remove it")
    if name in load_workspace(kit / "workspace.toml").repos:
        raise NewGameError(f"workspace.toml already has a repository called {name}")
    owner = kit_repo(kit).split("/")[0]
    holder = _check_text("the copyright holder", holder or owner, 100)
    full_name = f"{owner}/{name}"
    if options:
        github.preflight(gh, full_name)
    own_licence = licence_text(gh, licence, holder)
    words = substitutions(kit, name, template, title, description, holder)

    log(f"make    repos/{name} from the {template.name} template")
    repo.mkdir(parents=True)
    count = len(copy_tree(kit / "templates" / REPO_FOLDER, repo, words))
    for part in parts:
        count += len(copy_tree(part.path, repo, words, skip=frozenset({"template.toml"})))
    for rel in COPIED_FROM_KIT:
        (repo / rel).parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(kit / rel, repo / rel)
        count += 1
    if own_licence is not None:
        (repo / "LICENSE").write_text(own_licence.rstrip() + "\n", encoding="utf-8", newline="\n")
    log(f"write   {count} files, {licence} licence ({holder})")

    init = _git(run, repo, "init", "-b", "main")
    if init.returncode != 0:
        raise NewGameError(f"git init failed: {init.stderr.strip()}")
    if remote:
        _git(run, repo, "remote", "add", "origin", remote)
        log(f"git     origin = {remote} (nothing is pushed)")

    log(f"sync    {sync.sync(kit, repo, lambda line: None)} kit files written (agents, hook launcher, checker, hooks)")

    tools = load_tools(kit / "tools.toml")
    for tool in (t for t in tools.values() if t.kind == "godot-addon"):
        folder = root / "tools" / tool.folder
        if folder.exists():
            integrations.install_godot_addon(folder, tool.extra["addon"], tool.extra["source"], repo / "game", log)
        else:
            log(f"skip    {tool.name}: not fetched (`gds workspace init --fetch {tool.name}`), run it to install")

    todo: list[str] = []
    if shutil.which("git-lfs") or _git(run, repo, "lfs", "version").returncode == 0:
        _git(run, repo, "lfs", "install", "--local")
    else:
        log("skip    git lfs: not installed")
        todo.append("install Git LFS, then `git lfs install` in the repository")
    committed = _commit(run, repo, template, title, log)
    if not committed:
        todo.append("commit the files (`git add -A`, then a message that follows .github/conventions.yml)")
    if shutil.which("uvx"):
        installed = run(["uvx", "pre-commit", "install"], cwd=repo, capture_output=True, text=True, check=False)
        log("hooks   pre-commit, commit-msg and pre-push installed" if installed.returncode == 0 else "skip    hooks")
        if installed.returncode != 0:
            todo.append("run `uvx pre-commit install` in the repository")
        # Git LFS's pre-push, moved aside by pre-commit, starts `#!/bin/sh`, which pre-commit cannot find on Windows:
        # every push of the new game died on it until this repair, the one `gds worktree` makes (kit #779).
        for hook in worktrees.repair_legacy_hooks(repo / ".git" / "hooks"):
            log(f"hooks   {hook} started with #!/bin/sh, which pre-commit cannot find on Windows; repaired")
    else:
        log("skip    hooks: uvx is not installed")
        todo.append("run `uvx pre-commit install` in the repository")

    if options:
        if not committed:
            raise NewGameError(f"the first commit failed, so nothing was pushed; {repo} is staged")
        kit_full_name = kit_repo(kit)
        published = github.publish(
            repo,
            full_name,
            description,
            options,
            gh=gh,
            run=run,
            log=log,
            kit_pr=lambda done: github.open_kit_pr(
                run,
                gh,
                kit,
                kit_full_name,
                root / "worktrees" / kit_full_name.split("/")[1],
                root / "scratch",
                name,
                done,
                options.co_author,
                add_workspace_entry,
            ),
            **publish_with,
        )
        return Made(repo=repo, committed=committed, todo=todo + published.todo, published=published)
    if remote:
        if add_workspace_entry(kit, name, remote):
            log(f"write   workspace.toml: [repos.{name}] in {kit.name} (commit it in a kit pull request)")
            todo.append("commit the new workspace.toml entry in a kit pull request")
    else:
        todo.append(f"once the GitHub repository exists, add [repos.{name}] to the kit's workspace.toml")
    todo += _github_steps(name)
    return Made(repo=repo, committed=committed, todo=todo)


def _commit(run: Run, repo: Path, template: Template, title: str, log: Callable[[str], None]) -> bool:
    """Stage everything and make the first commit; False (staged only) when git has no identity to commit with."""
    _git(run, repo, "add", "-A")
    done = _git(run, repo, "commit", "-m", FIRST_COMMIT.format(title=template.title))
    if done.returncode != 0:
        log(f"skip    first commit: {(done.stderr or done.stdout).strip().splitlines()[-1:]}")
        return False
    log("commit  the starter files")
    return True


def _github_steps(name: str) -> list[str]:
    """What `--local` leaves out: the steps the command takes on GitHub without it."""
    return [
        f"create the GitHub repository for {name}, add it as `origin` and push `main`",
        "in its settings: Pages source = GitHub Actions; then `python .github/scripts/groundwork.py labels --apply`, "
        "`settings --apply` and `ruleset --apply` in the repository",
        "`gh workflow run hold-sweep.yml` once the ruleset requires `hold` (docs/studio/hooks.md#hold)",
    ]
