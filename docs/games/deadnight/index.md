# Deadnight

Deadnight is GDStudio's first game: a round-based co-op zombie survival game over one night at a 1958 drive-in
theater. The last reel of the season shows something it should not, and the audience does not stay dead. Up to eight
people (bots come on top) hold out round after round, buying their way deeper into the lot while keeping the generator
fed: the dead are faster in the dark. It is made with Godot 4.7 for the browser first, played in a tab or as a Discord
Activity, with an authoritative game server.

Its repository, [Ryubara/deadnight](https://github.com/Ryubara/deadnight), and its own docs site,
[ryubara.github.io/deadnight](https://ryubara.github.io/deadnight/), keep the day-to-day detail: the design pages, the
research (one page per subject, with the measurements), and the lessons that are about Deadnight alone. Development is
paused while the kit's foundation is built (`paused` in the kit's `workspace.toml`).

| Page | What it covers |
| --- | --- |
| [How it is built](building.md) | The project's layout, the client and server, the web build, the art, tests, bots and CI. |
| [Design philosophy](design-philosophy.md) | The three pillars and the choices that follow from them. |
| [Conventions](conventions.md) | The rules Deadnight adds to the kit's, and where its knowledge is written. |
| [Performance review](performance-review.md) | The first review made with the performance checklist: the tick measured, nine findings by cost, and what it could not see. |
