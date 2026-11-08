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
  lessons/         the record of problems hit, one file each (below)
```

Every folder has an `index.md` that says what belongs in it and what does not, and lists its pages. The navigation is
built from the folders (`index.md` first, titles from the headings), so adding a page never edits a shared file.

**Where a page goes.** Ask what the page is about, not who learned it or which kind of file it is:

| The page says | Folder |
| --- | --- |
| a principle that would hold in any engine (why a level reads, how loud a menu click is) | `gamedev/<subject>` |
| how an engine does something, what it costs, its traps | `engines/<engine>/` |
| how to do something in an asset tool, with the script that repeats it | `tools/<tool>/` |
| how agents, the hooks, CI, the workspace or the kit's tooling work | `studio/` |
| what one game is and how it is built, or a review of it the next game learns from | `games/<game>/` |

A subject with both a principle and an engine side gets a page in each, linked both ways (the principle in
`gamedev/`, the Godot specifics in `engines/godot/`). A folder of subpages under a topic (`gamedev/audio/`) is made
when a subject has more than one page. Another engine or tool gets its folder when a game needs it, never an empty
stub; a test fails an `engines/<name>/` that holds only its index.

**Lessons.** `docs/lessons/` stays as it is for now: one file per problem, with `areas:` front matter, the input of
`gds lessons <area>` and the SubagentStart hook. Its paths are part of the pull request rules (`Lessons:` lines), so it
did not move. #769 turns lessons into rules inside the topic sections; #770 migrates them and Deadnight's general docs.

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
  stays open: the `mkdocs.yml` has nothing Zensical-only, and MkDocs Material 9.7.7 still builds it strictly.

## Checks the old build hook ran {#checks}

The MkDocs build ran `.github/scripts/mkdocs_glossary.py`, which built the mistakes glossary page and failed the build
on a corrections row that quotes the maintainer (gdstudio #780 and #783). Zensical runs no hooks, so each check now
runs elsewhere and nothing is lost:

| Check | Where it runs now |
| --- | --- |
| Every lesson has `areas:` front matter naming known areas | `python .github/scripts/mistakes.py check`: pre-commit, pytest (`test_lessons.py`), and the docs job of CI |
| No corrections row quotes the maintainer (`lessons.quoted_rows()`) | the same check, and `test_the_kits_corrections_page_quotes_no_prompt` |
| The glossary can be built from the lessons and the corrections page | the same check; `gds lessons <area>` and the SubagentStart hook build it in memory |

A test fails a `hooks:` or `plugins:` key in `mkdocs.yml`: Zensical would ignore it without a word, and a check put
there would never run. A new check of the docs goes in pytest, pre-commit or the CI job.

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
| `research/mistakes-by-area.md` (generated) | removed; `gds lessons <area>` prints it |
