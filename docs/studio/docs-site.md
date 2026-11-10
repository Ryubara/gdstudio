# Docs site

The kit's docs site is laid out by topic and built by [Zensical](https://zensical.org/), pinned by exact version and
hash. This page is the one map of its folders: where a new page goes, how the site is built and checked, and what moved
when it left MkDocs (gdstudio #768). The issues that follow it (#769 lessons into rules in the topic sections, #770
lessons and Deadnight's general docs migrated, #771 `gds brief`) work from this map.

## The folders {#folders}

```text
docs/
  index.md         the home page: the sections below
  gamedev/         engine-neutral principles: animation, camera, input,
                   AI, netcode, audio, UI, level design, performance, tests
  engines/godot/   one engine: GDScript, scenes, physics, rendering,
                   animation, UI, export, networking, testing
  tools/blender/   one tool: modelling, UVs and texturing, materials,
                   baking, rigging, animation, optimisation, export
  studio/          how the studio works: agents, starting work, hooks,
                   CI, workspace, conventions, templates, this site
  games/<game>/    one game: summary, how we build it, design
                   philosophy, conventions
```

Every folder has an `index.md` that says what belongs in it and what does not, and lists its pages. The navigation is
built from the folders (`index.md` first, titles from the headings), so adding a page never edits a shared file; how it
is ordered and folded is [below](#nav).

**Where a page goes.** Ask what the page is about, not who learned it or which kind of file it is:

| The page says | Folder |
| --- | --- |
| a principle that would hold in any engine (why a level reads, how loud a menu click is) | `gamedev/<subject>` |
| how an engine does something, what it costs, its traps | `engines/<engine>/` |
| how to do something in an asset tool, with the script that repeats it | `tools/<tool>/` |
| how agents, the hooks, CI, the workspace or the kit's tooling work | `studio/` |
| a service beside the game that any game could have (a platform backend, its rules and traps) | `gamedev/<subject>` |
| how the studio deploys or runs something with a vendor's tool (Railway's CLI) | `studio/` |
| what one game is and how it is built, or a review of it the next game learns from | `games/<game>/` |

A subject with both a principle and an engine side gets a page in each, linked both ways (the principle in
`gamedev/`, the Godot specifics in `engines/godot/`). A folder of subpages under a topic (`gamedev/audio/`) is made
when a subject has more than one page. Another engine or tool gets its folder when a game needs it, never an empty
stub; a test fails an `engines/<name>/` that holds only its index.

**Inside a page.** What is learned updates the section it belongs to, never a page of its own: the format of an entry,
a section and its anchor is on [Learning in the topic pages](rules.md) (gdstudio #769). The old `docs/lessons/` (one
file per problem) was emptied into the sections by gdstudio #770 and takes no new file.

## The navigation {#nav}

The topics are tabs in the header: GDStudio (the home page), Game dev, Godot, Blender, Studio, Games. A tab's sidebar
holds only that topic, its sections folded shut until opened and nested to any depth (Games, then Deadnight, then its
pages); a section's title opens its `index.md`. On a phone the same tree is in the menu. The `mkdocs.yml` features that
do it are `navigation.tabs`, `navigation.indexes` and `navigation.prune` (a page carries only its own tab's tree, about
60 links on a Godot page instead of 1,070 on every page). `navigation.sections` stays off: it opens every group at once,
which is how the first Zensical site listed all 970 lessons in one column (gdstudio #790).

**What sets the order.** Zensical 0.1.0 reads three things, tested on the kit (#790):

- a `nav:` key in `mkdocs.yml`, which must name every page: a folder named there is a plain link to its index, not a
  section, and a page left out drops from the sidebar with no warning, even under `--strict`. The kit has none.
- `.nav.yml` files, one per folder, the format of the awesome-nav plugin, turned on by `plugins: [awesome-nav]`.
  Zensical reads them itself and runs no plugin code. **This is what the kit uses.**
- `weight:` front matter (mkdocs-nav-weight), not used.

A folder without a `.nav.yml` lists `index.md` first, then its pages and then its folders by file name. The files:

| File | What it says |
| --- | --- |
| `docs/.nav.yml` | the tab order; `flatten_single_child_sections`, so a folder with one child becomes that child |
| `docs/engines/.nav.yml`, `docs/tools/.nav.yml` | one folder each, so the tabs read Godot and Blender; a second engine or tool is listed here and the tab becomes Engines or Tools |
| `docs/studio/.nav.yml` | reading order; `append_unmatched: true` puts a new page after the listed ones |

A page or folder listed in a `.nav.yml` that does not exist fails the build. One left out of a list without
`append_unmatched` drops out of the sidebar silently, so a test fails a topic missing from `docs/.nav.yml` or an engine
or tool folder missing from its parent's. Sorting by title (`sort: {by: title}`) has no effect on our pages, whose
titles come from their headings, so Godot and Blender read in file-name order.

- **Approach:** Judge a change to a site, its theme or its nav by captures of the built pages at desktop and phone
  width with the biggest folder in view, and by the number of sidebar links a page carries, not by its build log.
  **Watch out for:** the move to Zensical kept `navigation.sections` from a site a tenth the size; a clean strict build
  and a full page count said every page was there, while the sidebar put all 970 lessons in one open group, about
  1,070 links and 450 KB on every page. **Seen:** gdstudio #790, 2026-11-08 (fix: topics are tabs, sections fold and
  nest, `navigation.prune` sends one tab's tree, `.nav.yml` sets the order, the lessons stay out of the nav, and a
  test fails `navigation.sections`).

## Building it {#build}

```sh
uvx --with-requirements requirements-docs.txt zensical build --strict
```

The site is written to `site/` and Zensical keeps a build cache in `.cache/`; both are ignored by git. `--strict` fails
the build on any warning: a link to a page that does not exist, or to an anchor a page does not have. A full build of
the kit (about 1,050 pages) takes under ten seconds. `zensical serve` serves it at `http://localhost:8000` while you
edit (its `--strict` is not supported yet, so check with `build`).

Zensical reads `mkdocs.yml` as it is: the theme (Material's features and palette), the Markdown extensions, `strict`.
CI (`.github/workflows/docs.yml`, the job still named `mkdocs` because that name is a required check) installs the
pinned requirements with `pip install --require-hashes`, runs `python .github/scripts/mistakes.py check`, builds with
`--strict`, writes the redirect pages, and on `main` publishes the site to GitHub Pages.

## The pin {#pin}

`requirements-docs.in` names the one direct dependency, `zensical==0.1.0`. `requirements-docs.txt` is compiled from
it with the exact version and sha256 hash of every file of every package, the dependencies included, the way
`python/uv.lock` pins the `gds` tool:

```sh
uv pip compile --generate-hashes --universal --python-version 3.12 requirements-docs.in -o requirements-docs.txt
```

To move to a new Zensical: change the version in the `.in` file, run that command, build with `--strict`, look at
the site, and open a pull request with screenshots before and after. A test fails a requirement line without a hash or
an `.in` version that the `.txt` does not match.

## How the 0.1 beta was judged {#beta}

Zensical 0.1.0 was published on 2026-11-05, after 71 releases of 0.0 since November 2025, and is marked beta on PyPI
(Development Status 4); it was taken on 2026-11-07.
What decided it:

- **Why move at all.** Material for MkDocs, the theme the site was built with, reaches end of life on 2027-05-05, and
  its team publishes Zensical as the successor (MIT licence). MkDocs 2.0 drops plugins and themes as they are, so
  staying meant a migration either way.
- **The trial.** On 2026-11-07 Zensical 0.1.0 rendered all 1,030 kit pages from the unchanged `mkdocs.yml`. Its only
  failures were the 10 links to the page our MkDocs hook generated, since Zensical runs no MkDocs hooks or plugins.
- **Strict mode is real.** A planted link to a missing page and one to a missing anchor each failed the build, as
  they did in MkDocs. A link to a file outside `docs/` is not checked by either.
- **Speed.** A cold build of the kit takes about 8 seconds, against about 17 for MkDocs.
- **What it lacks, and what we did.** No hooks or plugins: the generated glossary page is gone from the site (its
  checks moved, see [below](#checks)) and redirects are written by a script after the build (see [Moved
  pages](#moved)).
- **The risk.** It is a beta, so the version is pinned exactly and an upgrade is a reviewed pull request. The way back
  stays open: the `mkdocs.yml` has nothing Zensical-only, and MkDocs Material 9.7.7 still builds it strictly with the
  `mkdocs-awesome-nav` plugin installed for the [nav order](#nav).

## Checks the old build hook ran {#checks}

The MkDocs build ran `.github/scripts/mkdocs_glossary.py`, which built the mistakes glossary page and failed the build
on a corrections row that quotes the maintainer (gdstudio #780 and #783). Zensical runs no hooks, so each check now
runs elsewhere and nothing is lost:

| Check | Where it runs now |
| --- | --- |
| Every old lesson had `areas:` front matter naming known areas | dropped with the areas (gdstudio #771); the rest of `python .github/scripts/mistakes.py check` runs in pre-commit, pytest (`test_lessons.py`), and the docs job of CI |
| No corrections-log row quotes the maintainer (`lessons.quoted_rows()`) | the same check, and `test_the_kits_corrections_page_quotes_no_prompt` |
| The glossary can be built from the rules and the old lessons | dropped: the glossary is gone (gdstudio #771); a task agent's `Read:` lines name sections, which the Agent guard checks exist |
| The rules of the topic sections ([the list](rules.md#checks)) | the same check, with `--base HEAD^1` in CI (gdstudio #769) |

A test fails a `hooks:` key in `mkdocs.yml`, and a plugin Zensical does not implement itself (today only `awesome-nav`
is allowed): Zensical would ignore it without a word, and a check put there would never run. A new check of the docs
goes in pytest, pre-commit or the CI job.

## Moved pages {#moved}

The pages moved from the old layout by kind of file (`godot/`, `blender/`, `audio/`, `research/` and loose pages at the
top) to the topic folders. In the repositories, every link and path was rewritten. On the site, each old address still
works: `.github/site-redirects.toml` maps every old page to its new one, and `python .github/scripts/site_redirects.py`
writes a page at the old address that sends the reader on, keeping the `#anchor`. It fails when a new page is missing
from the build or an old address is a page again.

When a page moves later: `git mv` it in a commit of its own (no edits, so rename detection follows it for anyone
merging main), fix the links in the next commit, and add a line to the map.

| Old | New |
| --- | --- |
| `godot/` | `engines/godot/` |
| `blender/` | `tools/blender/` |
| `audio/` | `gamedev/audio/` |
| `agents.md`, `capture.md`, `hooks.md`, `refs.md`, `starting-work.md`, `sync.md`, `workspace.md` | `studio/` |
| `research/building-games-with-agents.md`, `maintainer-corrections.md`, `plan-from-the-start.md` | `studio/` |
| `research/level-design.md` | `gamedev/level-design.md` |
| `research/deadnight-performance-review.md` | `games/deadnight/performance-review.md` |
| `research/index.md` | removed; its pages are listed on [Studio](index.md) |
| `research/mistakes-by-area.md` (generated) | removed; the areas went too (gdstudio #771): `gds brief` names sections |

## Writing a page {#writing-pages}

<!-- new section: the page says how the site is laid out and built; nothing held what to check in a page before the
first push, where the strict build and markdownlint otherwise find it -->

- **Approach:** Run the strict docs build in the repository that holds the page (`uvx --with-requirements
  requirements-docs.txt zensical build --strict`) before the first push of any change that adds a link; copy an anchor
  from the target heading's `{#anchor}` instead of guessing it (every `##`/`###` heading under `studio/`, `engines/`,
  `tools/` and `gamedev/` has one, [Anchors](rules.md#anchors)), read the target's headings (`grep -n '^## '`), and
  link only files under `docs/` (name `AGENTS.md` in code). **Watch out for:**
  `AGENTS.md` sits at the repository root, which the site does not publish; a heading copied from the kit's page of the
  same name did not exist on the game's own page; a guessed anchor failed the build. **Seen:** gdstudio #432,
  2026-11-03; Deadnight #648, 2026-11-02; gdstudio, 2026-11-04.
- **Approach:** Name a docs page in a docstring or a code comment only as a path that exists, and keep
  `python/tests/test_docs_paths.py` green: it reads every `docs/...md` path in the docstrings of `python/src`,
  `.claude/hooks` and `.github/scripts`. When a page or a comment says what a file does, check it against the file
  when you change either. **Watch out for:** `gds_tools/cli.py` named `docs/tools.md` (the folder is `docs/tools/`), a
  CI comment still said the `template` job builds the 3D Blank game after it became a matrix over both templates, and a
  README said an addon names no game while its defaults are Deadnight's. **Seen:** gdstudio #920, 2026-11-10 (the #896
  review, table 2.5).
- **Approach:** Link a page of another repository by its full GitHub URL or name it as text, and use relative links only
  to pages of the same repository; link a page from another open pull request only after it lands, naming it in plain
  text until then; read every link of a row drafted by a game agent before it goes on a kit page. **Watch out for:** a
  relative link resolves against the page that holds it, so `[..](dead-contact.md)` pointed at Deadnight's research page
  and failed the kit's build; two open pull requests see two mains, so a page on its way counts as missing. **Seen:**
  gdstudio #478, 2026-11-04; Deadnight #1087, 2026-11-04.
- **Approach:** On a docs failure read `git diff origin/main --stat -- docs` before touching the link: a page that
  should only grow shows 0 deletions; before a report says a page was updated, grep the page for the heading the body
  names. **Watch out for:** a broken anchor was the only sign that 23 lines of another pull request's findings were gone
  and the new section never reached the page: its headings repeated older ones, which markdownlint refuses, and an edit
  put the numbers into the older section of that name. **Seen:** Deadnight #1129, 2026-11-04 (fix: `main`'s text
  restored and the section added whole, with headings of its own).
- **Approach:** Never start a wrapped line with an issue number (`#785's`, `#787 is`): rewrap so a word comes first.
  **Watch out for:** Markdown reads a line that starts with `#` as a heading, and markdownlint fails MD018 on a
  sentence. **Seen:** Deadnight, 2026-11-03 (fix: the lines rewrapped).
