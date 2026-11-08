"""The GitHub half of `gds new game` (docs/engines/godot/new-game.md#github): the repository, Pages, the conventions'
labels,
settings and ruleset, the hold sweep, the proof (the first CI run and the Pages deploy) and the kit pull request that
registers the game in workspace.toml.

Every `gh` call goes through `issues.run_gh`, the one runner, which refuses anything that would post a comment
(docs/studio/hooks.md#comments). Nothing here asks a question: an agent cannot answer stdin, so every choice is a flag
of the
command with a default. Making a new game repository public under MIT this way is the agent's to do (kit #779);
changing an existing repository's visibility or licence still waits for the maintainer.
"""

from __future__ import annotations

import json
import subprocess
import time
import urllib.error
import urllib.request
from collections.abc import Callable
from dataclasses import dataclass, field
from pathlib import Path

from gds_tools import pr
from gds_tools.issues import IssueError

Gh = Callable[[list[str]], str]
Run = Callable[..., subprocess.CompletedProcess]
Log = Callable[[str], None]

#: The workflows of a new game whose first run on `main` is the proof.
CI_WORKFLOW = "ci.yml"
DOCS_WORKFLOW = "docs.yml"
HOLD_SWEEP = "hold-sweep.yml"
#: The groundwork commands run with `--apply` in the new repository, in this order (the ruleset last: it names checks).
GROUNDWORK_STEPS = ("labels", "settings", "ruleset")
POLL_SECONDS = 20
#: A workflow pushed a moment ago is not dispatchable at once: how often and how long `hold-sweep` is retried.
DISPATCH_TRIES = 6
DISPATCH_PAUSE = 10
DEFAULT_WAIT_MINUTES = 45


class GitHubError(Exception):
    """A GitHub step failed; the message says which and what is left."""


@dataclass(frozen=True)
class Options:
    """The GitHub choices, each a flag of `gds new game` with its default."""

    private: bool = False
    wait: bool = True
    wait_minutes: float = DEFAULT_WAIT_MINUTES
    co_author: str = ""
    kit_pr: bool = True


@dataclass
class RunResult:
    """One workflow run: its conclusion ('' while it is still going or when none was found) and its page."""

    workflow: str
    conclusion: str = ""
    url: str = ""
    id: int = 0


@dataclass
class Published:
    """What the GitHub steps left: the repository, the proof and the kit pull request."""

    full_name: str
    url: str
    pages_url: str
    ci: RunResult | None = None
    docs: RunResult | None = None
    pages_live: bool = False
    kit_pr: str = ""
    todo: list[str] = field(default_factory=list)

    @property
    def green(self) -> bool:
        """The proof holds: CI and the docs deploy passed and the site answers."""
        ci = self.ci is not None and self.ci.conclusion == "success"
        docs = self.docs is not None and self.docs.conclusion == "success"
        return ci and docs and self.pages_live


def repo_url(full_name: str) -> str:
    return f"https://github.com/{full_name}.git"


def pages_url(full_name: str) -> str:
    owner, name = full_name.split("/")
    return f"https://{owner.lower()}.github.io/{name}/"


def preflight(gh: Gh, full_name: str) -> None:
    """Before a file is written: gh is signed in, and `full_name` does not exist yet."""
    try:
        gh(["auth", "status"])
    except IssueError as error:
        raise GitHubError(f"gh is not signed in ({error}); `gh auth login`, or make the game --local") from error
    try:
        gh(["repo", "view", full_name, "--json", "name"])
    except IssueError as error:
        if "Could not resolve" in str(error) or "not found" in str(error).lower():
            return
        raise GitHubError(f"cannot tell whether {full_name} exists: {error}") from error
    raise GitHubError(f"{full_name} exists on GitHub already; pick another name")


def create(gh: Gh, full_name: str, description: str, private: bool) -> None:
    """The empty repository, with the description and the Pages address as its homepage."""
    gh(
        [
            "repo",
            "create",
            full_name,
            "--private" if private else "--public",
            "--description",
            description,
            "--homepage",
            pages_url(full_name),
        ]
    )


def set_pages(gh: Gh, full_name: str) -> bool:
    """Pages' source = GitHub Actions. False when GitHub refused (an empty repository may refuse; retried later)."""
    for method in ("POST", "PUT"):
        try:
            gh(["api", "-X", method, f"repos/{full_name}/pages", "-f", "build_type=workflow"])
            return True
        except IssueError:
            continue
    return False


def push(run: Run, repo: Path, url: str) -> str:
    """`origin` = url, `main` pushed; the pushed commit's sha."""
    have = run(["git", "-C", str(repo), "remote"], capture_output=True, text=True, check=False).stdout.split()
    verb = "set-url" if "origin" in have else "add"
    run(["git", "-C", str(repo), "remote", verb, "origin", url], capture_output=True, text=True, check=False)
    done = run(["git", "-C", str(repo), "push", "-u", "origin", "main"], capture_output=True, text=True, check=False)
    if done.returncode != 0:
        said = "\n".join(part.strip() for part in (done.stdout, done.stderr) if part and part.strip())
        raise GitHubError(f"git push failed (a hook's report is in the lines above git's):\n{said}")
    head = run(["git", "-C", str(repo), "rev-parse", "HEAD"], capture_output=True, text=True, check=False)
    return head.stdout.strip()


def groundwork(run: Run, repo: Path, full_name: str, log: Log) -> None:
    """`groundwork.py labels|settings|ruleset -R <repo> --apply`, run with the game's own conventions."""
    for step in GROUNDWORK_STEPS:
        command = [*pr._python_command(), ".github/scripts/groundwork.py", step, "-R", full_name, "--apply"]
        done = run(command, cwd=repo, capture_output=True, text=True, check=False)
        if done.returncode != 0:
            raise GitHubError(f"groundwork.py {step} --apply failed: {(done.stderr or done.stdout).strip()}")
        log(f"github  groundwork {step} applied")


def hold_sweep(gh: Gh, full_name: str, sleep: Callable[[float], None]) -> bool:
    """Run hold-sweep.yml once; a workflow pushed seconds ago may not be dispatchable yet, so it is tried again."""
    for attempt in range(DISPATCH_TRIES):
        try:
            gh(["workflow", "run", HOLD_SWEEP, "-R", full_name])
            return True
        except IssueError:
            if attempt + 1 < DISPATCH_TRIES:
                sleep(DISPATCH_PAUSE)
    return False


def latest_run(gh: Gh, full_name: str, workflow: str, sha: str) -> RunResult | None:
    """The newest run of `workflow` for the commit `sha`, or None while GitHub has none."""
    try:
        out = gh(
            [
                "run",
                "list",
                "-R",
                full_name,
                "--workflow",
                workflow,
                "--commit",
                sha,
                "--json",
                "databaseId,status,conclusion,url",
                "-L",
                "5",
            ]
        )
    except IssueError:
        return None  # a workflow GitHub has not registered yet
    runs = json.loads(out or "[]")
    if not runs:
        return None
    first = runs[0]
    done = first.get("status") == "completed"
    conclusion = (first.get("conclusion") or "") if done else ""
    return RunResult(workflow, conclusion, first.get("url", ""), first["databaseId"])


def wait_run(
    gh: Gh,
    full_name: str,
    workflow: str,
    sha: str,
    deadline: float,
    sleep: Callable[[float], None],
    clock: Callable[[], float],
) -> RunResult:
    """Poll until the run of `workflow` for `sha` finishes or the deadline passes (conclusion '' then)."""
    last = RunResult(workflow)
    while True:
        found = latest_run(gh, full_name, workflow, sha)
        if found:
            last = found
            if found.conclusion:
                return found
        if clock() >= deadline:
            return last
        sleep(POLL_SECONDS)


def site_answers(url: str) -> bool:
    try:
        with urllib.request.urlopen(url, timeout=20) as response:  # noqa: S310 -- an https address we built
            return response.status == 200
    except (urllib.error.URLError, OSError, ValueError):
        return False


def wait_site(
    fetch: Callable[[str], bool],
    url: str,
    deadline: float,
    sleep: Callable[[float], None],
    clock: Callable[[], float],
) -> bool:
    """The deploy finished; the site can still take a minute to answer."""
    while True:
        if fetch(url):
            return True
        if clock() >= deadline:
            return False
        sleep(POLL_SECONDS)


def kit_title(name: str) -> str:
    return f"workspace: Add the {name} game"


def kit_body(name: str, published: Published, co_author: str) -> str:
    """The kit pull request's description, in the template's sections, so `check-body` accepts it."""
    model = co_author.split("<")[0].strip() if co_author else ""

    def run_line(result: RunResult | None, what: str) -> str:
        if not result or not result.url:
            return f"- {what}: not waited for (`--no-wait`)"
        return f"- {what}: {result.conclusion or 'still running'} ({result.url})"

    lines = [
        "<!-- markdownlint-disable-file MD041 -- a pull request body starts at the second heading level -->",
        "## Summary",
        "",
        f"- Registers the game `{name}` ({published.url.removesuffix('.git')}) in `workspace.toml`, so "
        "`gds workspace init` clones it. `gds new game` made the repository and opened this pull request.",
        "",
        "## Issues affected",
        "",
        "- None (a new game's entry in the workspace)",
        "",
        "## Checklist",
        "",
        f"- [x] `[repos.{name}]` in `workspace.toml`",
        "",
        "## Testing",
        "",
        run_line(published.ci, "the game's first CI run"),
        run_line(published.docs, "its docs deploy"),
        f"- the site {published.pages_url}: {'answers' if published.pages_live else 'not checked or not answering'}",
        "",
        "## Screenshots",
        "",
        "Screenshots: none (a line in workspace.toml)",
        "",
        "## AI use",
        "",
        f"- **Commits written by:** {'an AI' if model else 'a person'}",
        f"- **Model:** {model or 'n/a'}",
        "",
    ]
    return "\n".join(lines)


def open_kit_pr(
    run: Run,
    gh: Gh,
    kit: Path,
    kit_full_name: str,
    worktrees: Path,
    scratch: Path,
    name: str,
    published: Published,
    co_author: str,
    add_entry: Callable[[Path, str, str], bool],
) -> str:
    """A branch of the kit in its own worktree with `[repos.<name>]` added, pushed, and its pull request opened."""
    branch = f"workspace-add-{name}"
    path = worktrees / branch

    def git(*args: str, where: Path = kit) -> subprocess.CompletedProcess:
        done = run(["git", "-C", str(where), *args], capture_output=True, text=True, check=False)
        if done.returncode != 0:
            raise GitHubError(f"git {' '.join(args[:2])} in the kit failed: {(done.stderr or done.stdout).strip()}")
        return done

    git("fetch", "--quiet", "origin", "main")
    git("worktree", "add", "--no-track", "-b", branch, str(path), "origin/main")
    add_entry(path, name, published.url)
    title = kit_title(name)
    body = kit_body(name, published, co_author)
    checked = pr.check_body(path, body, title, kit=path)
    if not checked.ok:
        raise GitHubError("the kit pull request's description was refused: " + "; ".join(checked.reasons))
    message = title + (f"\n\nCo-Authored-By: {co_author}" if co_author else "")
    git("add", "workspace.toml", where=path)
    git("commit", "-m", message, where=path)
    git("push", "--quiet", "origin", branch, where=path)
    scratch.mkdir(parents=True, exist_ok=True)
    body_file = scratch / f"new-game-{name}-kit-pr.md"
    body_file.write_text(body, encoding="utf-8", newline="\n")
    out = gh(
        [
            "pr",
            "create",
            "-R",
            kit_full_name,
            "--base",
            "main",
            "--head",
            branch,
            "--title",
            title,
            "--body-file",
            body_file.resolve().as_posix(),
        ]
    )
    return out.strip().splitlines()[-1] if out.strip() else ""


def publish(
    repo: Path,
    full_name: str,
    description: str,
    options: Options,
    *,
    gh: Gh,
    run: Run,
    log: Log,
    url: str | None = None,
    kit_pr: Callable[[Published], str] | None = None,
    sleep: Callable[[float], None] = time.sleep,
    clock: Callable[[], float] = time.monotonic,
    fetch: Callable[[str], bool] = site_answers,
) -> Published:
    """Every GitHub step for a committed game in `repo`, in order. `url` is where `main` is pushed (the GitHub
    repository; a test gives a local bare repository)."""
    published = Published(full_name, repo_url(full_name), pages_url(full_name))
    create(gh, full_name, description, options.private)
    log(f"github  created {full_name} ({'private' if options.private else 'public'})")
    pages_early = set_pages(gh, full_name)
    sha = push(run, repo, url or published.url)
    log(f"github  pushed main ({sha[:9]})")
    pages_late = False
    if not pages_early:
        if not set_pages(gh, full_name):
            raise GitHubError(f"GitHub refused Pages for {full_name}: set its source to GitHub Actions by hand")
        pages_late = True
    log("github  Pages source = GitHub Actions")
    groundwork(run, repo, full_name, log)
    if hold_sweep(gh, full_name, sleep):
        log(f"github  {HOLD_SWEEP} started")
    else:
        published.todo.append(f"`gh workflow run {HOLD_SWEEP} -R {full_name}` (GitHub did not take it)")
    if options.wait:
        deadline = clock() + options.wait_minutes * 60
        log(f"wait    for the first CI run and the Pages deploy (at most {options.wait_minutes:g} minutes)")
        published.ci = wait_run(gh, full_name, CI_WORKFLOW, sha, deadline, sleep, clock)
        published.docs = wait_run(gh, full_name, DOCS_WORKFLOW, sha, deadline, sleep, clock)
        if pages_late and published.docs.conclusion == "failure" and published.docs.id:
            # The push's deploy can start before Pages exists; one rerun after it does is the fix, not a retry.
            gh(["run", "rerun", str(published.docs.id), "--failed", "-R", full_name])
            sleep(POLL_SECONDS)
            published.docs = wait_run(gh, full_name, DOCS_WORKFLOW, sha, deadline, sleep, clock)
        if published.docs.conclusion == "success":
            try:
                found = json.loads(gh(["api", f"repos/{full_name}/pages"]) or "{}").get("html_url")
                published.pages_url = found or published.pages_url
            except (IssueError, ValueError):
                pass
            published.pages_live = wait_site(fetch, published.pages_url, deadline + 300, sleep, clock)
        for result in (published.ci, published.docs):
            log(f"{result.workflow:<7} {result.conclusion or 'not finished'} {result.url}".rstrip())
        log(f"pages   {published.pages_url} {'answers' if published.pages_live else 'does not answer'}")
    else:
        published.todo.append(f"watch the first CI run and the Pages deploy of {full_name} (`--no-wait`)")
    if options.kit_pr and kit_pr:
        published.kit_pr = kit_pr(published)
        log(f"kit     pull request {published.kit_pr}")
    return published
