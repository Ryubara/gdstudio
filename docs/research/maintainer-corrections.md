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
| The deployed build hitches the first time something appears (a shot, a zombie) | We measured frame times on desktop and with a warm browser profile, and nothing drew every effect once before play | Warm up behind a loading screen from the first night; measure in a browser with a fresh profile and count the GL programs linked during play ([First-use hitches](../godot/first-use-hitches.md)) |
| Add mobile controls for landscape play, intuitive and researched | We planned for desktop and the browser but not for phones, although Discord Activities run on them | Name every input device the game ships on (keyboard and mouse, gamepad, touch); plan touch controls, landscape lock and safe areas with the first playable build |
| The dead's animation should follow their speed and the round | Speeds were retuned (#260) without the clips that show them; blend points were guesses, so fast zombies slid | Measure each locomotion clip's ground speed; any change to movement speed checks foot slide and gait in the same pull request |
| Guns must be scaled, angled and placed right on the player | Weapons were attached once and never checked against the hands, the shoulder and the aim ray | Each held item has a grip, support and barrel check in tests and a side, shoulder and aim capture |
| Keep research pages and this page up to date as work lands | Findings stayed in agent reports and pull request bodies | Each pull request updates the research page it builds on; each correction lands here the same evening |

## Found by playing: concepts and details we missed

The maintainer played the build with a mouse, a gamepad and a browser and found these within minutes. Every system
had passing tests. Each row names the **concept** nobody planned for and the **detail** that was built without being
checked, so the next game plans the first and tests the second.

| The maintainer found | Concept missed | Detail missed | Check for next time |
| --- | --- | --- | --- |
| The mouse did not turn the camera, in the editor and in the browser | Nobody played with a real mouse; tests called the look handler directly, so the real input path was never exercised | Three full-screen Controls (the game's `Main` root, the router's `Stage`, the night screen) kept Godot's default `mouse_filter` STOP and marked every motion handled; a headless test run skips GUI mouse handling, so it could not see it | Containers that only hold screens or a world are `MOUSE_FILTER_IGNORE`; a test lists every mouse-catching Control over a running level, with the real main scene loaded; the browser smoke moves the mouse and asserts the view turned |
| The gamepad worked only sometimes | Device identity: pads are numbered as they connect, and a reconnect or a virtual pad changes the number | Every gameplay binding was tied to device 0 | Bind actions to all devices (`-1`) unless the game has local split screen; a test drives play from a pad that is not device 0 |
| A slightly moved mouse made the pad look undetected | Input mode is a guess from the last event | Any mouse motion, however small, switched the glyphs to keyboard | Ignore pointer noise (a few pixels) when choosing the input mode |
| Weapons switched in the rules but not on screen; the guns sat wrong in the hands | The view must follow the game state for every item, not one sample item | `equip` was never called outside tests; holds were copied from a one-handed pose and models were at real length while the player scene is scaled | A capture per weapon after each swap; a test that every catalogue weapon shows its own model, grip, support hand and barrel on the aim ray |
| Firing from the hip did not turn the character or tighten the camera | Genre controller conventions were not listed before building the controller | Shots went down the camera ray while the body kept its old facing | Before a controller is built, list the reference genre's conventions (hip-fire turn, hip-fire zoom, ADS, sprint rules) and check each in a capture |
| No crosshair | A basic element of the genre's HUD was missing while the HUD was polished | The HUD placed items "beside the crosshair" that did not exist | Inventory the genre's HUD elements (reticle, hit marker, ammo, prompts) against the design before polishing layout |
| Repair took one press per board | Hold-to-interact is the genre's convention for repeated actions | Interact was a single press for every use | For each interaction decide press or hold against the reference and write it in the design |
| No camera shake on firing | Feel ("juice") was not a planned pass | Nothing reacted to firing but the sound | Plan a feel pass per verb (shake, kick, flash, hit feedback), every amount exported so it is tuned in the editor |
| The muzzle flash was a yellow sphere; bullet impacts were far too large | Placeholder effects shipped as final because no task owned them | Sizes were never compared against the character | Every placeholder is listed in an issue when it lands; effects are captured next to the character for scale |
| The ammo count did not update after buying ammo until a weapon swap | UI driven by one-off events instead of by state | The ammo card re-read only on equip | HUD values are bound to the replicated state and refresh on any change; a test buys ammo and reads the HUD without a swap |
| The look saved in the wardrobe did not show on the character in the game | Parts built and tested one by one (save, wire format, server, look table, assembler) were counted as a working feature; nobody followed a look from the wardrobe into a game | The player scene held a fixed model, so there was nothing for a look to dress, and no join message carried the look | A feature that crosses screens gets one test on the real path (save through the real file, enter the real level, read what the player sees) before it counts as done |
| The fire effect has to start at each weapon's muzzle | Attachment points belong to the model: whoever models a weapon places its muzzle, grip and support hand | The muzzle was a fixed offset from the body, the same for every gun, so the flash sat away from the barrel | Every firearm carries a `Muzzle` empty at the barrel tip (-Z out of the barrel), placed in Blender; a test checks it sits at the barrel end and that the flash spawns on it |
| Each player looked different on the other player's screen in a two-window game | Appearance is replicated state with one owner, the server; every view, the player's own body included, dresses from that one table | The night dressed bodies only on the loopback path, never over the network link, and two windows on one machine shared one settings file | A test with two clients over the real socket checks that every player shows the same parts and colours on every client and on the server; a `--look` flag gives local windows different looks |
| A player was taller on the other player's screen | Local and remote bodies are one scene, or share one transform | The player scene turned its model half round and scaled it 0.8; remote avatars did neither, so they were a quarter taller and faced the camera | The same two-client test compares skeleton height, scale and facing per player on every client and on the server |
| Camera shake was asked for as "very subtle" and came for firing only; sprinting had none | A feel request names a quality, not one verb | Shake was built for the verb in front of us (firing), and "subtle" had no number, so the shotgun reached 0.63 degrees | List every verb a feel request can apply to (fire, sprint, land, hit, blast) and confirm it; write "subtle" as a number (peak degrees) in the design and hold it in a test |
| The character could not sprint backwards; omni-directional movement felt wrong | The reference genre's controller conventions (free movement facing the travel, sprint in any direction when not aiming, strafe when aiming) were not listed | Sprint was tied to forward input; the sprint camera pull-back distance and speed were never tuned against a reference | Before building a controller, test a matrix from day one: 8 directions, aimed and not aimed, walk and sprint; camera reactions to movement are tuned numbers in the design doc |
| Sometimes the settings rows collapse into each other | An entrance animation that moves a container's children depends on when the container lays them out; it was only ever tested from a script, never from a real click | `UIMotion.stagger_in` read each row's position one frame after the tab showed, before the container's deferred sort, and a page never shown sits at (0, 0) | UI motion is tested through real input events, at low and high physics tick rates, switching every tab in every order mid-transition, with no rows overlapping ([lesson](../lessons/2026-11-01-container-children-read-before-the-deferred-sort.md)) |

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
| The browser smoke read the game's probe through a list of named fields, so a new field (the camera yaw) read as missing and the first look check failed on a working build | Running the check against both a fixed and an unfixed build | Probes pass the whole object through, or a test checks every published field reaches the page |
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

- Play every build for ten minutes with a mouse and keyboard and with a gamepad, in the editor and in the browser,
  before calling a feature done.

- Touch controls (landscape, safe areas, no browser scroll or zoom) planned with the first playable build when the
  game ships in a browser or Discord.

### AI teammates

- Decide whether bots fill player slots; if so, research them (perception, aim, movement, economy, revives) first.

### Testing and recordings

- Every feature names its proof; every visual PR carries before/after captures.
- Recordings use the player's camera.

### Process on a shared machine

- Cap load tests, stop processes by PID, time out long commands, and warn neighbouring projects first.

### First use

- Load and draw every enemy, weapon, effect and light state once behind a loading screen; keep the materials of
  short-lived effects alive.
- A browser run with a fresh profile that counts programs linked after the loading screen is the gate (zero).

### Hosting

- A playable web build is live from the first playable night and redeploys on merge.
