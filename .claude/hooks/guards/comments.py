"""No comment or review under the maintainer's account, judged on what `gh` would do (docs/studio/hooks.md#comments)."""

from __future__ import annotations

import re
from urllib.parse import unquote

from .merges import api_call
from .shell import program, segments, strip_heredocs

# The commands that exist to post (`gh help` of gh 2.102), and those that post when they carry `--comment` or `-c`.
_COMMENT_COMMANDS = {("issue", "comment"), ("pr", "comment"), ("discussion", "comment"), ("pr", "review")}
_CLOSING_COMMANDS = {("issue", "close"), ("pr", "close"), ("issue", "reopen"), ("pr", "reopen")}
# The mutations of GitHub's schema that add, edit or submit a comment or a review.
_COMMENT_MUTATIONS = re.compile(
    r"\b(addComment|addDiscussionComment|addPullRequestReview\w*|dismissPullRequestReview|submitPullRequestReview"
    r"|updateDiscussionComment|updateIssueComment|updatePullRequestReview\w*)\b"
)
_NO_COMMENTS = (
    "nothing is posted as a comment or review under the maintainer's GitHub account (their decision of 2026-10-12). "
    "Run the command without the text (`gh issue close N`) and put the text in your scratch folder and your report, "
    "for the maintainer to post; a capture goes on a pull request or a new issue with `--attach` "
    "(docs/studio/hooks.md#comments)"
)
# Words that start another program on the same line, and the arguments they take before it.
_LAUNCHERS = {"then", "do", "else", "elif", "if", "while", "until", "!", "{", "try", "env", "command", "timeout"}
_LAUNCHERS |= {"nohup", "xargs"}
_LAUNCHER_ARG = re.compile(r"[-\d{]|\w+=")
_SHELLS = {"bash", "sh", "zsh", "dash", "pwsh", "powershell", "cmd", "eval"}
_SHELL_FLAG = re.compile(r"-\w+|/[a-zA-Z]")
_CONTINUATION = re.compile(r"(?:\\|(?<=\s)`)\r?\n")  # a line continued in bash, or in PowerShell
_SINGLE_QUOTED = re.compile(r"'[^'\n]*'")
_INNER_GH = re.compile(r"(?:\$\(|`|\{\s)\s*(?=(?:[^\s'\"(){}]*[/\\])?gh(?:\.exe)?\s)")


def launched(words: list[str]) -> list[str]:
    """The words from the program a simple command runs: past `then`, `(`, `env X=1`, `timeout 30`, `xargs -n1`."""
    words = [words[0].lstrip("("), *words[1:]]
    i = 0
    while i < len(words) and (words[i] in _LAUNCHERS or (i and _LAUNCHER_ARG.match(words[i]))):
        i += 1
    return words[i:]


def gh_calls(command: str) -> list[list[str]]:
    """Every `gh` command a shell line runs, also inside `bash -c '...'`, `eval` and `$(...)`, as words. Text that only
    mentions one is left out: an `echo`, a commit message, a `grep`, a single-quoted body, a heredoc."""
    text = _CONTINUATION.sub(" ", strip_heredocs(command))
    found: list[list[str]] = []
    for simple in segments(text):
        words = launched(simple)
        if not words:
            continue
        name = program(words)
        if name == "gh":
            found.append(words)
        elif name in _SHELLS:
            args = words[1:]
            while args and _SHELL_FLAG.fullmatch(args[0]):
                args = args[1:]
            found += gh_calls(" ".join(args))
    bare = _SINGLE_QUOTED.sub("''", text)
    for inner in _INNER_GH.finditer(bare):
        found += gh_calls(re.split(r"[)`}\n]", bare[inner.end() :], maxsplit=1)[0])
    return found


def gh_route(words: list[str]) -> tuple[str, ...]:
    """The group and the command of a `gh` command. `-R` and a misplaced `--comment` may stand before them: gh takes
    `gh issue -R o/r close 5`, and cobra hands a flag it finds there to the command."""
    route: list[str] = []
    i = 1
    while i < len(words) and len(route) < 2:
        word = words[i]
        i += 1
        if word in ("-R", "--repo", "--comment", "-c"):
            i += 1
        elif not word.startswith("-"):
            route.append(word.rstrip(")"))
    return tuple(route)


def comment_flag(words: list[str]) -> str | None:
    """`--comment` or `-c` as gh reads it on a close or reopen (`--comment=x`, `-cx`, `-c=x`, the cluster `-dc x`), or
    None. The value of an option that takes one is not read as an option: `--reason -c`, `-Rco/r`."""
    i = 1
    while i < len(words):
        word = words[i]
        i += 1
        if word == "--":
            return None
        if word.startswith("--"):
            flag, has_value, _ = word.partition("=")
            if flag == "--comment":
                return flag
            i += flag in ("--repo", "--reason", "--duplicate-of") and not has_value
        elif word.startswith("-"):
            for position, letter in enumerate(word[1:], 2):
                if letter == "c":
                    return "-c"
                if letter in "Rr":
                    i += position == len(word)  # the value is the next word, or the rest of this one
                    break
    return None


def api_comment(words: list[str]) -> str | None:
    """What is wrong with a `gh api` call that posts a comment or a review: a write to a path with a `comments` or
    `reviews` part, a mutation that posts one, or a GraphQL query that is not on the command line to be read."""
    method, endpoints, fields = api_call(words)
    paths = [unquote(re.split(r"[?#]", endpoint, maxsplit=1)[0]) for endpoint in endpoints]
    if any(path.rstrip("/").endswith("graphql") for path in paths):
        found = _COMMENT_MUTATIONS.search(" ".join(fields))
        if found:
            return f"the GraphQL mutation `{found.group(1)}` posts one"
        if not any(field.startswith("query=") and "{" in field.replace("${", "") for field in fields):
            return "a GraphQL query from a file or a variable cannot be read for a comment: write it in the command"
        return None
    if method in ("POST", "PATCH", "PUT") and any({"comments", "reviews"} & set(path.split("/")) for path in paths):
        return f"`gh api -X {method}` to a comments or reviews path posts one"
    return None


def comment_route(words: list[str]) -> str | None:
    """How a `gh` command posts a comment or a review, or None when it posts neither."""
    route = gh_route(words)
    if route[:1] == ("api",):
        return api_comment(words)
    if route in _COMMENT_COMMANDS:
        return f"`gh {' '.join(route)}` posts one"
    if route in _CLOSING_COMMANDS:
        flag = comment_flag(words)
        return f"`gh {' '.join(route)} {flag}` posts one" if flag else None
    if route == ("alias", "set"):  # an alias would hide the route from this guard on every later use
        calls = [call for text in words[3:] for call in gh_calls(f"gh {text}") + gh_calls(text.lstrip("!"))]
        return next(filter(None, map(comment_route, calls)), None)
    return None


def check_comments(command: str) -> list[str]:
    """The rule against comments under the maintainer's account (docs/studio/hooks.md#comments), judged on what `gh`
    would do,
    not on a list of the commands named `comment`: `gh issue close --comment` put one on #691."""
    routes = filter(None, map(comment_route, gh_calls(command)))
    return [f"{route}: {_NO_COMMENTS}" for route in routes]
