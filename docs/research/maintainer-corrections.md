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
| Add mobile controls for landscape play, intuitive and researched | We planned for desktop and the browser but not for phones, although Discord Activities run on them | Name every input device the game ships on (keyboard and mouse, gamepad, touch); plan touch controls, landscape lock and safe areas with the first playable build |
| The dead's animation should follow their speed and the round | Speeds were retuned (#260) without the clips that show them; blend points were guesses, so fast zombies slid | Measure each locomotion clip's ground speed; any change to movement speed checks foot slide and gait in the same pull request |
| Guns must be scaled, angled and placed right on the player | Weapons were attached once and never checked against the hands, the shoulder and the aim ray | Each held item has a grip, support and barrel check in tests and a side, shoulder and aim capture |
| Keep research pages and this page up to date as work lands | Findings stayed in agent reports and pull request bodies | Each pull request updates the research page it builds on; each correction lands here the same evening |

## Done wrong first, caught by our own checks

Mistakes the maintainer did not have to point out, because a test, a measurement or a review caught them. Each one is
also a check to keep.

| What went wrong first | What caught it | Check |
| --- | --- | --- |
| Two pull requests each passed the balance gate alone; merged together (#260 speeds, #271 crane price) they broke it on `main` | The gate on the next pull request | Rerun the balance gate on `main` after each merge that touches tuning; one balance owner rebases on the others |
| A merge of `main` doubled a step in a test, so the branch failed | The night suite after the merge | After a conflicted merge, read the diff of every test file against `main` before rerunning |
| World triplanar materials slowed the web frame from 79 to 90 ms | A frame-time measurement in the browser | Measure frame time on the web build for every material or lighting change |
| A headless import left new textures without mipmaps | Looking at the far ground in a capture | Check `.import` settings of new 3D textures in review |
| Walk and run blend points were guessed (1.0 and 3.0 m/s; the clips measure 0.97 and 4.4) | Measuring the planted foot | Measure clip speeds before setting any blend threshold |
| Guns were modelled at real length while the player scene scales the Soldier to 0.8 (the rifle was as long as the Soldier is tall), held from a one-handed pose with the barrel 21 degrees up, and every gun showed the rifle because nothing called `equip` | Measuring hands, stock and barrel against the aim ray (Deadnight #288) | Scale held items by one written rule against the character's in-game height; test grip, support hand, stock and barrel per weapon; a capture per weapon proves the right model shows |
| A balance fix ran only the gate test; four simulator tests around the code it changed failed in CI, so `main` stayed red past the deadline | CI on the fix | Before opening, run the whole suite folder of every file changed, not only the test the change aims at |
| Main's CI cancelled in-progress runs when the next merge landed, so four of five merges in three minutes were never checked | The evening review (Deadnight #290, fixed in #296) | `cancel-in-progress` only for pull requests; every run on the default branch finishes |
| A pull request body wrote `None` without the expected form | The body check in CI | Run `groundwork.py check-body` locally before opening |

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
- Locomotion rate follows the actor's speed; clip ground speeds are measured, not guessed.
- Held items are checked against the hands, the shoulder and the aim ray.

### Every input device

- Touch controls (landscape, safe areas, no browser scroll or zoom) planned with the first playable build when the
  game ships in a browser or Discord.

### AI teammates

- Decide whether bots fill player slots; if so, research them (perception, aim, movement, economy, revives) first.

### Testing and recordings

- Every feature names its proof; every visual PR carries before/after captures.
- Recordings use the player's camera.

### Process on a shared machine

- Cap load tests, stop processes by PID, time out long commands, and warn neighbouring projects first.

### Hosting

- A playable web build is live from the first playable night and redeploys on merge.
