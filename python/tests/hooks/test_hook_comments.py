"""Comments (docs/studio/hooks.md#comments): every route in gh 2.102's manual, and what must keep working."""

from __future__ import annotations

import pytest
from hook_support import denied, patch, shell

# The command that put the closing comment on #691, as it was run.
CLOSE_691 = (
    'gh issue close 691 -R Ryubara/gdstudio --comment "$(cat "C:\\Users\\Noah\\scratchpad\\close.md")" '
    "&& gh issue view 691 -R Ryubara/gdstudio --json state,labels -q '.state'; df -k /c | tail -1"
)
COMMENT_COMMANDS = [
    "gh issue comment 5 --body hi",
    "gh issue comment 5 --body '/claim'",
    "gh issue comment 5 --body /release",
    "gh issue comment 5 -b hi --attach a.png",
    "gh issue comment 5 -F body.md",
    "gh issue comment 5 --edit-last -b hi",
    "gh pr comment 5 --body hi",
    "gh pr comment --edit-last --create-if-none -b hi",
    "gh discussion comment 5 --body hi",
    "gh discussion comment DC_abc --edit --body hi",
    "gh pr review 5 --approve",
    "gh pr review 5 --comment --body hi",
    "gh pr review 5 -r -b hi",
    "gh pr review",
]
CLOSE_COMMANDS = [
    "gh issue close 5 --comment hi",
    "gh issue close 5 --comment=hi",
    "gh issue close 5 -c hi",
    "gh issue close 5 -c=hi",
    "gh issue close 5 -chi",
    'gh issue close 5 --reason completed --comment "two words"',
    "gh pr close 5 --comment hi",
    "gh pr close 5 --comment=hi",
    "gh pr close 5 -c hi",
    "gh pr close 5 -dc hi",
    "gh pr close 5 --delete-branch -c hi",
    "gh issue reopen 5 --comment hi",
    "gh issue reopen 5 -c hi",
    "gh pr reopen 5 --comment hi",
    "gh pr reopen 5 -c hi",
]
ROUTE_SPELLINGS = [
    CLOSE_691,
    "gh issue -R o/r close 5 --comment hi",
    "gh issue --repo=o/r comment 5 -b hi",
    "gh pr -R o/r review 5 --approve",
    "gh issue --comment hi close 5",
    '"gh" issue close 5 "--comment" hi',
    "gh.exe issue close 5 -c hi",
    "'C:\\Program Files\\GitHub CLI\\gh.exe' issue close 5 -c hi",
    "& gh issue close 5 -c hi",
    "GH_REPO=o/r gh issue close 5 -c hi",
    "env GH_REPO=o/r gh issue close 5 -c hi",
    "timeout 30 gh issue close 5 -c hi",
    "command gh issue close 5 -c hi",
    "echo 5 | xargs gh issue close -c hi",
    "if true; then gh issue close 5 -c hi; fi",
    "(gh issue close 5 -c hi)",
    "(gh pr review)",
    "try { gh issue close 5 -c hi } catch {}",
    "5, 6 | ForEach-Object { gh issue close $_ -c hi }",
    "gh api -iX POST repos/o/r/issues/5/comments",
    "x=$(gh issue close 5 -c hi)",
    'echo "$(gh pr comment 5 -b hi)"',
    "echo `gh pr comment 5 -b hi`",
    "bash -c 'gh issue close 5 -c hi'",
    "sh -lc 'cd x && gh issue close 5 -c hi'",
    'pwsh -Command "gh pr close 5 -c hi"',
    "cmd /c gh issue close 5 -c hi",
    "eval 'gh issue close 5 -c hi'",
    "gh issue close 5 \\\n  --comment hi",
    "gh issue close 5 `\n  --comment hi",
    "cd sub && gh issue close 5 -c hi",
    "gh alias set done 'issue close --comment finished'",
    "gh alias set note 'issue comment 5 --body hi'",
]
API_COMMANDS = [
    "gh api repos/o/r/issues/5/comments -f body=hi",
    "gh api repos/o/r/issues/5/comments -fbody=hi",
    "gh api repos/o/r/issues/5/comments --raw-field body=hi",
    "gh api repos/o/r/issues/5/comments --field=body=hi",
    "gh api repos/o/r/issues/5/comments -F body=@note.md",
    "gh api repos/o/r/issues/5/comments --input note.json",
    "gh api -X POST repos/o/r/issues/5/comments",
    "gh api -XPOST repos/o/r/issues/5/comments",
    "gh api --method=post repos/o/r/issues/5/comments",
    "gh api --method POST /repos/{owner}/{repo}/issues/5/comments -f body=hi",
    "gh api https://api.github.com/repos/o/r/issues/5/comments -f body=hi",
    "gh api -H 'Accept: application/json' repos/o/r/issues/5/comments -f body=hi",
    "gh api -X PATCH repos/o/r/issues/comments/9 -f body=hi",
    "gh api repos/o/r/pulls/5/comments -f body=hi",
    "gh api repos/o/r/pulls/5/comments/9/replies -f body=hi",
    "gh api -X PATCH repos/o/r/pulls/comments/9 -f body=hi",
    "gh api repos/o/r/pulls/5/reviews -f event=COMMENT",
    "gh api repos/o/r/pulls/5/reviews/9/events -f event=APPROVE",
    "gh api -X PUT repos/o/r/pulls/5/reviews/9 -f body=hi",
    "gh api -X PUT repos/o/r/pulls/5/reviews/9/dismissals -f message=hi",
    "gh api repos/o/r/commits/abc/comments -f body=hi",
    "gh api -X PATCH repos/o/r/comments/9 -f body=hi",
    "gh api gists/abc/comments -f body=hi",
    "gh api -X PATCH gists/abc/comments/9 -f body=hi",
    "gh api repos/o/r/discussions/5/comments -f body=hi",
    "gh api orgs/o/teams/t/discussions/5/comments -f body=hi",
]
# Every mutation of GitHub's schema that adds, edits or submits a comment or a review (asked of the API on 2026-11-05).
COMMENT_MUTATIONS = [
    "addComment",
    "addDiscussionComment",
    "addPullRequestReview",
    "addPullRequestReviewComment",
    "addPullRequestReviewThread",
    "addPullRequestReviewThreadReply",
    "dismissPullRequestReview",
    "submitPullRequestReview",
    "updateDiscussionComment",
    "updateIssueComment",
    "updatePullRequestReview",
    "updatePullRequestReviewComment",
]
GRAPHQL_UNREADABLE = [
    'gh api graphql -f query="$QUERY"',
    "gh api graphql -F query=@mutation.graphql",
    "gh api graphql --input mutation.json",
    'gh api graphql -f query="$(cat mutation.graphql)"',
]
ALLOWED_COMMANDS = [
    "gh issue close 5",
    "gh issue close 5 --reason completed",
    "gh issue close 5 -r 'not planned' -R o/r",
    "gh issue close 5 --reason -c",
    "gh issue close 5 -Rco/r",
    "gh issue close 5 --duplicate-of 4",
    "gh pr close 5",
    "gh pr close 5 --delete-branch",
    "gh pr close 5 -d",
    "gh issue reopen 5",
    "gh pr reopen 5",
    "gh pr merge 5 --squash",
    "gh pr merge 5 --squash --body 'the commit text' --subject 'a title'",
    "gh issue view 5 --comments",
    "gh issue view 5 -c",
    "gh pr view 5 --comments",
    "gh pr view 5 -c",
    "gh discussion view 5 --comments",
    "gh issue list --search comments",
    "gh issue create --title x --body y --attach a.png",
    "gh issue edit 5 --body y",
    "gh pr edit 5 --title y",
    "gh pr edit 5 --add-reviewer someone",
    "gh pr ready 5",
    "gh search issues --commenter me",
    "gh help issue comment",
    "gh help pr review",
    "gh alias set co 'pr checkout'",
    "gh api repos/o/r/issues/5/comments",
    "gh api repos/o/r/issues/5/comments --paginate --jq '.[].body'",
    "gh api --method GET repos/o/r/issues/5/comments -f per_page=100",
    "gh api repos/o/r/pulls/5/reviews",
    "gh api -X DELETE repos/o/r/issues/comments/9",
    "gh api -X DELETE repos/o/r/pulls/comments/9",
    "gh api repos/o/r/issues/5/labels -f 'labels[]=A-hooks'",
    "gh api repos/o/r/pulls/5/requested_reviewers -f 'reviewers[]=someone'",
    "gh api repos/o/r/issues -f title=x -f body='see /comments'",
    "gh api graphql -f query='{ viewer { login } }'",
    'gh api graphql -f query=\'{ repository(owner:"o", name:"r") { pullRequest(number:1) { id } } }\'',
    "gh api graphql -f query='mutation { closeIssue(input:{issueId:\"I\"}) { clientMutationId } }'",
    "gh api graphql -f query='query($n:Int!){ viewer { login } }' -F n=1",
    "uv run --project python gds issue start Ryubara/gdstudio#695 --agent claude",
    "echo gh issue comment 5 --body hi",
    "echo 'gh issue close 5 --comment hi'",
    'grep -n "gh issue close --comment" docs/studio/hooks.md',
    "git log --grep 'gh pr comment'",
    "git commit -m 'hooks: Refuse gh issue close --comment'",
    "git commit -m \"$(cat <<'EOF'\ngh issue close 5 --comment hi\nEOF\n)\"",
    "cat > note.md <<'E'\ngh issue close 5 --comment hi\nE",
    "gh pr view 5 --jq '.body' | grep 'gh issue comment'",
    "gh issue create --title x --body 'never run `gh issue comment` here'",
    "bash -c 'gh issue close 5'",
    "python -c 'print(1)'",
]


def test_a_comment_posted_while_closing_is_refused_with_the_way_out(tmp_path):
    reason = denied(shell(CLOSE_691, tmp_path))
    assert "`gh issue close --comment`" in reason and "under the maintainer's GitHub account" in reason
    assert "gh issue close N" in reason and "scratch" in reason


@pytest.mark.parametrize("command", COMMENT_COMMANDS + CLOSE_COMMANDS + ROUTE_SPELLINGS + API_COMMANDS)
def test_every_gh_route_that_posts_a_comment_is_refused(tmp_path, command):
    assert "under the maintainer's GitHub account" in denied(shell(command, tmp_path))


@pytest.mark.parametrize("mutation", COMMENT_MUTATIONS)
def test_every_graphql_mutation_that_posts_a_comment_is_refused(tmp_path, mutation):
    command = f"gh api graphql -f query='mutation {{ {mutation}(input:{{}}) {{ clientMutationId }} }}'"
    assert "under the maintainer's GitHub account" in denied(shell(command, tmp_path))


@pytest.mark.parametrize("command", GRAPHQL_UNREADABLE)
def test_a_graphql_query_the_guard_cannot_read_is_refused(tmp_path, command):
    assert "cannot be read for a comment" in denied(shell(command, tmp_path))


@pytest.mark.parametrize("tool", ["Bash", "PowerShell"])
def test_the_comment_guard_covers_both_shell_tools(tmp_path, tool):
    payload = shell("gh issue close 5 --comment hi", tmp_path) | {"tool_name": tool}
    assert "under the maintainer's GitHub account" in denied(payload)


@pytest.mark.parametrize("command", ALLOWED_COMMANDS)
def test_what_is_not_a_comment_keeps_working(tmp_path, monkeypatch, command):
    patch(monkeypatch, "held", lambda target, repo, cwd: False)
    assert denied(shell(command, tmp_path)) == ""
