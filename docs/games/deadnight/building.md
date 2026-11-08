# How Deadnight is built

<!-- new section: games/deadnight/ held only the performance review; the summary pages join it with gdstudio #770 -->

The short version for an agent new to the game; each part links to the Deadnight page that holds the detail.

## The project {#project}

`game/` is the Godot project: `core/` autoloads, settings and the probes, `gameplay/` the rules, weapons, zombies and
bots, `net/` the protocol, the server and the client, `world/` the maps, `ui/` the screens and the Deadnight skin,
`assets/` models, textures and audio, `tests/` the GdUnit4 suites by subject. `deploy/` holds the game server and
backend images for Railway, `spikes/` the backend service and the network spikes the protocol started from, `tools/`
the Python tools (balance simulator, bot soak, web smoke, CI sharding, Blender scripts). The scenes and where every
tuning number lives are on Deadnight's [Scenes](https://ryubara.github.io/deadnight/design/scenes/) and
[Tuning](https://ryubara.github.io/deadnight/design/tuning/) pages.

## Client and server {#net}

One authoritative headless Godot server runs the night on a fixed 30 Hz tick: the rules, the player simulation and the
zombies are plain data in and plain data out, so the server owns them. Clients send inputs, the server sends delta
snapshots against the last one each client acknowledged; a client predicts and reconciles its own player and
interpolates everything else. The protocol is Deadnight's own over a plain WebSocket, not Godot's MultiplayerAPI,
chosen for about eight times less download per player; a single-player night runs the same server inside the game
over a loopback link. The decision and its numbers are on Deadnight's
[Networking](https://ryubara.github.io/deadnight/design/networking/) page; the kit's general page is
[Multiplayer](../../engines/godot/multiplayer.md).

## The web build {#web}

The browser is the first platform, so the Compatibility renderer (WebGL2) is the only one used, and a feature that needs
Forward+ or Mobile is not. The build is played on phones held sideways with an on-screen control layer, on desktops
with mouse and keyboard or a gamepad, and inside Discord as an Activity. What the web runtime does differently is on
the kit's [Web export](../../engines/godot/web-export.md) and [Web heap](../../engines/godot/web-heap.md) pages; the
phone controls on Deadnight's [Touch controls](https://ryubara.github.io/deadnight/design/touch-controls/).

## Art {#art}

The starting art is the Quaternius Toon Shooter Game Kit and the Quaternius zombie (CC0, credited on the Credits
screen); its characters share one rig, so animations are shared by bone name. The measured rules (proportions, bevels,
triangle budgets, palette) are Deadnight's [Style bible](https://ryubara.github.io/deadnight/design/style/); the
pipelines are the kit's [Blender](../../tools/blender/index.md) pages.

## Proof {#proof}

GdUnit4 suites run headless in CI in shards; the UI suites that need a window run nightly under xvfb. An autopilot
plays whole nights through the real input, bots play beside people, and a nightly soak plays ten nights per cell of
its matrix. A browser smoke run (`tools/web_smoke/`) loads the web export in headless Chrome and counts what a frame
costs. What each CI job does and when it starts is on Deadnight's
[CI jobs](https://ryubara.github.io/deadnight/research/ci-jobs/) page; the kit's testing principles are
[Testing](../../gamedev/testing.md).
