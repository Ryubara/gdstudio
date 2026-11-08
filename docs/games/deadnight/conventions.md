# Deadnight's conventions

<!-- new section: games/deadnight/ held only the performance review; the summary pages join it with gdstudio #770 -->

Deadnight follows every rule of the kit's `AGENTS.md`; its own `AGENTS.md` adds these.

- **Compatibility renderer only.** The web build is WebGL2.
- **Every third-party asset has a licence entry**, and its credit reaches the Credits screen.
- **Proof, not claims.** Visual work carries screenshots or clips attached to its pull request; audio work a clip with
  the sound as its track.
- **Docs stay short.** One page per subject, updated in place; link instead of repeating.
- **Titles** use Deadnight's areas: `core`, `gameplay`, `ui`, `net`, `world`, `art`, `audio`, `build`, `ci`,
  `agents`, `docs`, `tests`.

## Where its knowledge goes {#knowledge}

- **Design** (what the game is, as it stands): Deadnight's `docs/design/`, one page per subject.
- **Research** (what was learned building it, with the measurements): Deadnight's `docs/research/`.
- **A lesson about Deadnight alone** (its maps, its zombies, its economy, its HUD): Deadnight's `docs/lessons/`. The
  lessons that held for any game were folded into the kit's topic pages with gdstudio #770; a new general learning
  goes to the kit's topic section in a kit pull request, named on the game pull request's `Kit docs:` line
  ([Where the entry is named](../../studio/rules.md#named)).
