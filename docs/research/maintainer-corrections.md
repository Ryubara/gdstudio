# What the maintainer caught

During Deadnight's first night of work, the maintainer corrected or added things that neither the coordinator nor
any agent had proposed first. Each one points to a blind spot that will come back on the next game. This page lists
them and turns each into a check to run when a new game or feature starts.

## Corrections and the checks they become

| The maintainer said | Blind spot | Check for next time |
| --- | --- | --- |
| Build multiplayer on our own protocol and backend, network-first, not the engine's built-in multiplayer | We reached for the engine default instead of the game's constraints (browser players, hosting cost) | Before any netcode: who plays where (browser, Discord, desktop), the bandwidth per player, where the server runs; compare options with measured numbers |
| Balance and a proper wave system are part of the concept, not extras | We treated the reference genre as a list of features, not as a tuned loop | Name the reference game's core loop and its tuning; plan a balance simulator and its gate with the first systems |
| Add boss rounds and zombie types, clearly announced | We copied the base loop and missed the variety that keeps it interesting | List the reference's variety beats (bosses, special rounds, enemy types) and how each is signalled to the player |
| Screenshots and videos on every issue and PR, before and after | Work was judged from text, so nobody saw what changed | Every visual change carries uploaded before/after captures; a PR without them fails its checks |
| Agents test everything themselves; nothing is handed to the user to try | "Please try it" was the default proof | Each feature names its own proof: input simulation, a bot run, audio analysis, a browser run |
| An "Issues affected" section and a "Failed first" test in PRs (from Coney) | Follow-up work and real regressions went untracked | PR template carries both from day one; the coordinator updates every affected issue after a merge |
| The kit has few guns; make more weapons in its style | We assumed the starter kit was enough content | Inventory the starter kit against the game's needs and plan the gaps as art tasks |
| HUD: resembling the reference is fine, but text is misaligned and the HUD too big | The HUD was judged in isolation, not at real resolutions | Capture the HUD at 720p, 1080p and 1440p and on the web build; measure alignment and overflow in tests |
| Points as `[portrait][colour points]`, not "PLAYER 1 POINTS" | We labelled data instead of designing for a glance in a fight | For each HUD element ask what the player reads in half a second, and design that |
| The generator panel shows only when progress is made; no ammo under the health bar | Every system got an always-on panel, some twice | One home per number; panels for slow progress appear on change and leave |
| The game is over the shoulder: record from the player's camera | We filmed the bot through a spectator camera | Recordings and captures use the camera the player has |
| A closer, fluid shoulder camera like Battlefront II | Camera feel came after systems | Pick a reference camera at the start and tune framing, damping and interpolation before content |
| Textures and the kit's own props would go a long way | The greybox lingered while systems grew | Put materials and kit props on the map early, as soon as the layout holds |
| Board tearing and repair need real animation | Interactions shipped as state changes with a stand-in effect | Every interaction gets its animation (actor clip and object motion) in the same feature, or an issue |
| Research zombie speed against player walk and sprint in the reference | Movement numbers were set without the reference's ratios | Collect the reference's movement numbers (enemy tiers per round, player walk, sprint, aim) before tuning |
| Research AI teammate bots in depth: revive, buy, move, all weapons | Our bot was a test tool, not a teammate | Decide early whether the game needs bot teammates; if so, research them before building the systems they use |
| (From a neighbouring project) 93 Godot processes held the CPU at 100% | Load tests had no limit on a shared machine | At most four parallel suites, no busy loops, stop by PID, a timeout on every long command, a heads-up before long load tests |
| Host the web build on Railway | Shipping a playable link came late | Stand up a playable web build early and redeploy it on every merge |

## Start of a new game

### Feel and camera

- Name the reference camera and tune it (framing, damping, render interpolation, aim and sprint transitions) first.
- Look at the game from the player's view every day, not only through tests.

### Movement and numbers against the reference

- Collect the reference game's numbers (movement, enemy tiers by round, damage, economy) and cite them.
- Build the balance simulator on the real weapons and tuning, with a gate in CI.

### HUD at real resolutions

- Capture every HUD change at 720p, 1080p, 1440p and in the browser; test alignment and overflow.
- One place per number; transient panels for slow progress.

### Art beyond the greybox early

- Inventory the starter kit against the design; plan the missing content.
- Materials and kit props on the map as soon as the layout holds.

### Animation for every interaction

- Each interaction (repair, buy, revive, tear) ships with its actor clip and object motion.

### AI teammates

- Decide whether bots fill player slots; if so, research them (perception, aim, movement, economy, revives) first.

### Testing and recordings

- Every feature names its proof; every visual PR carries before/after captures.
- Recordings use the player's camera.

### Process on a shared machine

- Cap load tests, stop processes by PID, time out long commands, and warn neighbouring projects first.

### Hosting

- A playable web build is live from the first playable night and redeploys on merge.
