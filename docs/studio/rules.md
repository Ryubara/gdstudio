# Learning in the topic pages

<!-- new section: no page held where a learning goes and its format; docs-site.md says where pages go -->

What an agent learns, from its own mistake or from a maintainer correction, goes into the topic page an agent reads
for that task (an engine page, a Blender page, a studio page), in the same task, as a short entry in the page's own
voice: the **approach** to take, what to **watch out for**, and where it was **seen**. A bad keyframe goes under the
keyframes section of the Blender or Godot animation page; a hook that misread a path goes under the hook's section of
[Hooks](hooks.md). The page gets better each time; nobody writes a page for one mistake (gdstudio #769).

There are no lesson pages and no lesson categories. `docs/lessons/` (one file per problem, the old way) takes no new
file, a check refuses one; #770 empties it, moving the general files into topic pages and Deadnight's into the
Deadnight repository.

## Where a learning goes {#where}

Into the page someone opens while doing that work, under the section about that subject, never into a pile of its own.
Ask what the agent was doing when it needed the knowledge, not who learned it or when.

- **Approach:** Put a learning into the topic page an agent reads for that task, never into a new page of its own.
  **Watch out for:** knowledge kept in a separate pile of 960 per-mistake pages is not where an agent looks while
  working, and the start hook fed each agent the newest 12 items of its areas, not the ones that fit its task.
  **Seen:** gdstudio #769, 2026-11-08 (fix: lessons stopped being a kind of page; entries live in topic sections,
  `gds learn` finds the closest, and the start hook injects the sections closest to the issue).

## Find the section first {#find}

```sh
uv run --project python gds learn <topic or words>
```

`gds learn` searches the topic pages and prints the sections closest to the words, best first, each as
`page.md#anchor` with its entries (`--old N` adds the closest old lesson files while #770 runs). Read them before
writing: when a section already has the entry, add where you saw it to its `Seen:`; when it has one close to yours,
sharpen that one. Only when nothing fits do you make a new section, and only when a topic outgrows its page a new page.

- **Approach:** When several agents work in one worktree, run `git status --short docs/` and `gds learn <topic>` right
  before making a new page or section, not only when the task starts. **Watch out for:** an agent checked
  `docs/gamedev/` at the start, found no HUD or controller page, and made `gamedev/hud.md`, while other agents were
  making `gamedev/ui.md#hud` and `gamedev/controller.md`, so the topics were duplicated. **Seen:** gdstudio #769,
  2026-11-07 (fix: the entries were moved into `ui.md#hud` and `controller.md`, and `hud.md` was deleted before the
  report).

## An entry {#rule}

One list item, in three labelled parts, in this order:

```markdown
- **Approach:** Key every bone on the first and last frame of a looping clip. **Watch out for:** an unkeyed bone
  keeps the pose of the clip played before, so the loop pops. **Seen:** Deadnight #1234, 2026-11-05 (fix: the walk
  clips were keyed again and a test compares the first and last frames of every loop).
```

- `Approach:` what to do, as an instruction someone can follow next time, not the story of what went wrong.
- `Watch out for:` what goes wrong when the approach is not kept, and why.
- `Seen:` where it happened, the issue or pull request (`Deadnight #1234`, `gdstudio #769`) and the date, with how it
  was fixed and the test or check that now catches it in parentheses. An entry seen again gets another source here
  (`; Deadnight #1301, 2026-11-06`), not a second entry.

The whole item is at most 900 characters, wrapped lines indented two spaces. It says what the maintainer pointed out
in our words, never as a quote of the prompt (gdstudio #780). An entry from a maintainer correction also gets a line
on the [corrections log](maintainer-corrections.md). The old form (`**Rule:** ... **Why:** ... **Fix:**`) is refused.

- **Approach:** Record what the maintainer decided or pointed out in our words, with its source (issue or pull request,
  date), never the prompt, here or anywhere in a public repository. **Watch out for:** the corrections page and the
  learning hook were designed around quoting the maintainer, so every row copied a prompt into a public repository.
  **Seen:** gdstudio #780, 2026-11-07 (fix: the quotes were removed, and the checks fail a corrections-log row with a
  cell that starts with a quotation mark).

## A section {#section}

A section is a `##` or `###` heading of a topic page, with an explicit anchor. Entries sit in it beside its prose,
usually at the end:

```markdown
## Keyframes {#keyframes}

How the clips are keyed, and why ...

- **Approach:** ...
```

A section that holds an entry has an explicit `{#anchor}`; the check fails one that does not. When you add an entry to
a section that has none yet, give it the anchor its heading already had (the heading's words in lowercase, joined with
hyphens), so the links to it keep working.

**A new section** has a reason line right under its heading, an HTML comment that says why no existing section fits:

```markdown
## Root motion {#root-motion}

<!-- new section: the keyframes and retargeting sections are about poses; nothing covered moving the body -->
```

The check compares the docs with `origin/main` (CI: the pull request's base): a heading whose anchor the base page does
not have needs the reason line, unless the heading above it is new as well. Renaming a heading keeps its `{#anchor}`,
so a rename is not a new section. **A new page** has the reason line under its `#` title, is listed in its folder's
`index.md`, and goes where [Docs site](docs-site.md#folders) says.

## Anchors {#anchors}

What links to a section, from a pull request, a report or a tool (`gds learn`, the `Read:` lines of #771, the
corrections log), names it as `<page>#<anchor>`:

- **The page** is its path under `docs/`, with or without that prefix: `engines/godot/ui-controls.md#focus` and
  `docs/engines/godot/ui-controls.md#focus` name the same section.
- **The anchor** is the explicit `{#anchor}` of the heading: lowercase letters, digits and single hyphens
  (`[a-z0-9]+(-[a-z0-9]+)*`), unique on its page.
- **Anchors are stable.** A heading may be reworded, its anchor stays. A section that moves to another page takes its
  anchor along, and every link to it is changed in the same pull request (the strict docs build fails a link to an
  anchor that does not exist).
- `lessons.anchors(path)` reads a page's anchors and `lessons.parse_ref("page.md#anchor")` reads a reference: tools
  use those two, not their own pattern.

- **Approach:** When you give a long heading its implicit `{#anchor}`, count the line: past 120 columns, shorten the
  heading's words and keep the anchor, or choose a shorter anchor when nothing links to the heading yet. **Watch out
  for:** the anchor repeats the heading, so a heading over about 58 characters passes markdownlint's 120 (MD013 checks
  headings), and a heading cannot wrap. **Seen:** gdstudio #769, 2026-11-07 (fix: headings in crowds.md and
  web-export.md were reworded with their anchors kept, and two unlinked ones took short anchors, found by a width check
  before the report).

## Page size {#size}

A page holds at most 50 KB. A topic that grows past it becomes a folder of subpages (as `gamedev/audio/` did): the
one time a learning makes a new page. The check names the page and its size.

## Where the entry is named {#named}

- **A task agent's report.** Its `Mistakes` section names each section it updated as `page.md#anchor`. The
  SubagentStop hook refuses a report whose Mistakes section names no section that exists and that a kit worktree
  changes against `origin/main` (`Mistakes: none` when nothing went wrong).
- **A pull request.** A fix, a rework, or a pull request after a failed check carries `Lessons: <page.md#anchor>` in
  its Summary, naming the topic section that the pull request updates; `pr-rules` checks the anchor's page is among its
  changed files. A pull request that closes an issue names the areas it read first (`Read first: <areas>`).
- **A game's pull request.** A general learning goes to the kit's topic section in a kit pull request, named on the
  game pull request's `Kit docs:` line; a learning about that game alone goes to the game's own docs.

## The checks {#checks}

`python .github/scripts/mistakes.py check` runs in pre-commit, in pytest and in the docs job of CI. It refuses:

| Refused | Why |
| --- | --- |
| A file under `docs/lessons/` that the base does not have, or one dated after 2026-11-07 | a learning updates a topic section instead |
| A page over 50 KB | a topic that big is split into a folder |
| A new heading without a reason line | a section is made only when none fits |
| An entry without its three parts in order, over 900 characters, or in a section without an explicit anchor | the format above |
| An entry in the old `**Rule:**` form | the format above |
| A duplicate or malformed `{#anchor}` on a page | a reference must name one section |
| A row of the corrections log that quotes the maintainer or links no section | the log says what was pointed out in our words and where its entry lives |
| An old lesson file without `areas:` front matter | the old files keep building until #770 empties the folder |

The numbers live in `.github/conventions.yml` under `learning` (a test keeps `lessons.py` equal to them).

## What no program sees {#unseen}

A mistake the agent does not report is invisible to every check: no hook knows a test was rerun until it passed, or
that a first attempt was wrong. The [reviewer](agents.md) looks for it: a fix commit after a red check, a reverted
approach, a capture that changed between pushes. A mistake found that way gets its entry like any other, and the
reviewer names the missing report in its verdict.
