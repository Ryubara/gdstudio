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
| Whenever you merge something, pull the latest changes into the local main; it should have been set up from the start | Merges landed on GitHub (most by auto-merge) while the local main checkouts, which the maintainer opens in the editor, stayed behind | A workspace keeps every local main fast-forwarded after each merge, automatically (a hook), never by memory; a checkout with local changes is named, never discarded |
| No round time limits at all; a 3x zombie count means a 3x spawn rate too | A count multiplier was read as more zombies over a longer round, and an unasked time limit was added with an overtime rule | A multiplier on a game setting scales the intensity the player feels (count and rate together), not the duration; add no limit or fail rule the maintainer did not ask for |
| Over 100 zombies at once on desktop, easily, without lag (RTX 5080, 9800X3D) | A crowd ceiling measured on the web build (40) became the one ceiling for every platform, so desktop never had a budget of its own | Every performance cap names the platform it was measured on; measure each shipped platform (desktop client, browser, headless server, network) and give each its own number |
| The dead's animation should follow their speed and the round | Speeds were retuned (#260) without the clips that show them; blend points were guesses, so fast zombies slid | Measure each locomotion clip's ground speed; any change to movement speed checks foot slide and gait in the same pull request |
| Guns must be scaled, angled and placed right on the player | Weapons were attached once and never checked against the hands, the shoulder and the aim ray | Each held item has a grip, support and barrel check in tests and a side, shoulder and aim capture |
| Keep research pages and this page up to date as work lands | Findings stayed in agent reports and pull request bodies | Each pull request updates the research page it builds on; each correction lands here the same evening |
| Mouse controls work, but moving the mouse doesn't turn the camera (on the web, after the fix in Deadnight #299 merged) | A fix counted as done when it merged, not when it was live where the maintainer plays: a flaky leak check (#317) failed main's CI three times, so the deploy job never ran and the site kept the old build, and nobody looked | After a merge that fixes something the maintainer reported, watch main's deploy, run the same probe against the live URL (for mouse look, the yaw probe), then tell the maintainer it is live |
| Spawned Godot windows that agents use shouldn't take my cursor focus; then: the cursor no longer jumps, but my keyboard still goes to the Godot window | Agents share the maintainer's machine while the maintainer works on it: every windowed Godot run (captures, recordings, autopilot) became the active window, and stopping the mouse capture did not stop Windows giving it the keyboard | Every windowed tool run starts off the person's desktop (`gds godot`, a private desktop); a hook refuses a bare windowed Godot; the proof is that keystrokes still reach the person's window, not only that the mouse stayed put |
| Make sure we update docs on stuff I've had to correct, and enforce it | Learning from corrections depended on the coordinator remembering; no hook or rule tied a correction to a docs change, and agents did not read past corrections before starting | Hooks: a reminder on every prompt, the checks read at session and agent start, a stop gate on unpublished queued rows (kit #72) |
| We have PRs up from 2-3 hours ago, why aren't these merged? Do we have a conflict or failing label? | Merge throughput was not planned: many parallel PRs touched the same hot files, a flaky required check stalled main, PRs were stacked, and nothing showed a PR's state at a glance | Fix a red main before anything else; one owner per stuck PR; work the queue oldest first; agents only on files no open PR touches; `S-conflict` / `S-ci-failing` labels kept in sync (kit #76) |

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
| From the side, my character looks blurry and jittery when I move | Fixed-step physics needs drawing between ticks; the camera's smoothing was built alone and the body was never checked against it | The camera blended the last two ticks by hand while `physics_interpolation` was off, so a smooth camera framed a body that stepped every two or three frames on a 120-165 Hz screen; at 60 Hz nothing showed | Turn on physics interpolation in the first playable build; test on-screen position at 144 fps over 60 ticks ([Physics interpolation](../godot/physics-interpolation.md)) |
| I'm unable to throw grenades at the moment | A feature wired only into its test range counted as shipped because the keys, HUD, shop, sounds and clips around it existed | Grenades were connected to `world/grenade_range` only; the night server never created them, and each link was tested alone (Deadnight #351, #356) | Every feature has a test that presses the real input in the real night; one matrix test presses every gameplay action on every device and fails on an action with no row |
| The crowbar is a baseball bat model, has no swing, makes a muzzle flash, and its blows don't work; the revolver does not show in the hand | Every catalogue weapon is a feature of its own, played in the night; a known gap is the maintainer's to hear about, not a design-page line | Melee went through the gun effects; no game code played the attack clips (only capture scripts did); the melee sweep started at the camera 2.3 m behind the player; the bat stood in for the crowbar and the pistol had no hold, and tests pinned both stand-ins as expected (Deadnight #285, [lesson](../lessons/2026-11-01-a-catalogue-weapon-was-never-played-in-the-night.md)) | One play-through test per catalogue entry (real input, real night: model, clip, effects, result); never assert a stand-in as correct; a shipped gap is reported to the maintainer; captures drive the real path |
| Firing without aiming does not put the gun into the aiming animation; aiming makes the gun "teleport" into position; the hip-fire zoom should be the same logic as aiming, and zooming out after hip fire takes longer | Firing from the hip is the aim state entered for a moment, not a second, partial aim: one weight should drive camera, body and hands | Hip fire got its own camera spring (half the zoom, in at 14 and out at 7 against the aim's 24, after a 0.8 s hold) and the animation read only the aim button; the gun's aim yaw and support-hand convergence were switched by a bool while only the legs eased (Deadnight #300) | One aim weight per character, entered by aiming or a recent shot, read by every system; a test that hip fire and aiming reach the same camera and pose and release in the same time; every pose input that follows a state is blended, with a bound on the per-frame change of the hand target ([lesson](../lessons/2026-11-01-hip-fire-was-a-second-partial-aim.md)) |
| "I'm trying the web version right now and I don't see the results of this working. It's the same as before" (the side-view judder, after its fix was closed) | A setting a node inherits has to be proved in the tree the game builds, on the platform the maintainer plays | Physics interpolation was switched on and measured in a test room under a plain `Node`; in the game the night hangs under a UI screen (a `Control`), which switches it off for everything below, and the web measurement had been split into a follow-up nobody started (Deadnight #344, #353) | Assert `is_physics_interpolated_and_enabled()` on the real body in the real screen; prove a reported fix on the reported platform (the live web build) before its issue closes, never as a split-off follow-up ([lesson](../lessons/2026-11-01-a-control-above-the-3d-world-switched-interpolation-off.md)) |
| The voice lines "sound a bit robotic and like an AI": it says "Reload", "Catch my breath", but really it should be "Reloading!", "Jeez, gotta catch my breath real quick", like a real person talking with expression, with a lot of variety | A bark is a person reacting in the moment, not a caption for the event | The first sample line was written as instructions to the player ("Reload... catch your breath"), short and clipped, with no fillers, contractions or exclamations, so the voice read it like a narrator (Deadnight #384) | Write each line as the character speaking under stress (first person, contractions, a filler or breath, an exclamation where it fits), read it aloud before generating, and plan many takes per event so nothing repeats; a catalog test fails any line with no performance mark and fewer than four words (Deadnight #442) ([lesson](../lessons/2026-11-01-voice-lines-written-as-captions-sounded-robotic.md)) |
| "My cursor gets auto focused still when agents are testing, it gets locked in between an invisible box on my screen, as if the window is invisible (I can still hear audio)" | Protecting the person at the machine covers every global input state a program can take, not only the focus: the cursor clip, the clipboard, global hotkeys | The no-focus launcher moved windows to a private desktop and was measured for focus and keys only; a game capturing the mouse calls `ClipCursor`, which crosses desktops and held the real cursor to the hidden window (kit #77) | The launcher sets `GDS_QUIET=1` and every game skips mouse capture under it; a test clips the cursor from the hidden desktop and asserts the real one stays free ([lesson](../lessons/2026-11-02-a-hidden-capture-held-the-cursor-in-an-invisible-box.md)) |
| "Is the 'this machine's own' applicable when deployed to web...? How does this work when creating lobbies and rooms for other users?" (the Join screen offered `ws://localhost:8910` in the browser) | Players play with friends, not with addresses: the player-facing flow is rooms (Discord instance, invite link, code, quick join), and a server address is a developer tool | The Join screen built for the networking spike shipped as the online menu; the backend's lobbies and allocation were built and tested but never deployed or wired into the menu (Deadnight #391) | Before an online feature is called playable, walk the flow a stranger takes on each platform the game ships on (browser, Discord); no address, port or localhost in any player-facing screen |
| "Camera shake when sprinting is too intensive, we should lower this down by 50%. Camera should not shake when running and jumping and still holding shift while in the air"; then "increase default camera FOV by 10%", meaning the view should feel closer to the character | Footfall-driven camera motion belongs to feet on the ground, not to the sprint state; and "increase the FOV" was read as wider when the maintainer meant closer | `SprintSway.step` took only the sprint flag and speed, which stay set in the air, so a sprint-jump swayed as on the ground; the rig was never given `on_floor`. FOV was first widened 70 to 77, the opposite of the ask (Deadnight #405, #426: FOV 60, aim 40, sprint 63, sway halved) | Any motion keyed to steps takes the grounded state and a test steps it through the first airborne tick; camera numbers get a sprint, sprint-jump and long-play capture. A feel request worded two ways is restated as a number and a visible result and confirmed before building ([lesson](../lessons/2026-11-02-sprint-sway-kept-going-in-the-air.md)) |
| "Muzzle flash could be improved as well, need agent to investigate why it's a bit weaker than it seems." | An effect is judged by what it does to the pixels from the player's camera, in the player's renderer, not by its parameters or a close-up capture | From the shoulder camera the flash was 0.02 to 0.14 % of the screen and 2 frames long, its quads lay in the muzzle's plane so the gun, hand and arm hid 25 to 87 % of them, and its light went under the floor when the gun pointed down (Deadnight #408, #448) | Measure a readable effect on the screen before and after (draw the frame again without it), from the real camera, hip and aimed, desktop and browser, and hold the numbers as floors in a test; draw quads near the player's own mesh toward the camera ([lesson](../lessons/2026-11-02-a-flash-in-the-guns-plane-was-hidden-by-the-gun.md), [method](../godot/measuring-effects-on-screen.md)) |
| "The logic to replicate the aiming zoom whenever you hipfire should not trigger at all when a user is already aiming... whenever I aim and shoot, then let go of aim -- it's triggering the hipfire zoom still" | A shot while aiming is not hip fire; the hold that imitates aim belongs only to shots from the hip | The aim weight was held while `fire_age < hip_fire_hold`, and every shot reset `fire_age` (Deadnight #428, #433) | When two states share one output, test every transition between them, not only each state alone ([lesson](../lessons/2026-11-02-aim-release-kept-the-hip-fire-zoom.md)) |

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
| UI input tests passed alone and failed in the folder run: a menu left on the router by an earlier suite took the clicks | CI, then running the suites in order (Deadnight #346) | Clear the router before any test that sends mouse or touch input; run a new input test inside its whole folder ([lesson](../lessons/2026-11-01-ui-input-test-fails-only-in-the-folder-run.md)) |
| A smoothness test measured frames timed by the real clock and failed on busy machines, turning main red | Main's CI and a local run (Deadnight #362) | Measure per-frame motion in a child Godot at `--fixed-fps`, with control cases that must fail ([lesson](../lessons/2026-11-01-a-smoothness-test-read-the-real-clock.md)) |
| The maintainer's real mouse turned a capture's camera by up to 65 degrees | Two runs of the same capture script that differed (Deadnight #364) | Captures switch off the driven player's device input ([lesson](../lessons/2026-11-01-the-real-mouse-turned-a-capture-camera.md)) |
| The first soldier voice samples were made on ElevenLabs `eleven_v3`, chosen from memory, while the account offered `eleven_v4` ("most emotive"); the maintainer asked "Are we using the best available model?" | The maintainer (Deadnight #384) | Before generating with a vendor API, list its current models (`GET /v1/models`) and pick from that list; say in the PR which model and why ([lesson](../lessons/2026-11-01-a-voice-model-was-picked-from-memory.md)) |
| Test suites saved `camera_shake=0` through the game's `Settings` autoload into the player's real `user://settings.cfg`; the maintainer's game lost its camera shake and two agents "fixed" it by editing the real file | Spurious test failures on other branches, then agents comparing notes (Deadnight #418, #446) | A game with a settings or save autoload points it away from `user://` from the first test, and a test fails if a suite run changes the real file; agents never edit `app_userdata`, they report it ([lesson](../lessons/2026-11-02-tests-wrote-the-players-settings.md)) |

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
- A state that changes a pose (aim, sprint, crouch) reaches it through one eased weight; nothing in the pose flips
  on a bool.

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
- Every catalogue entry (weapon, item, perk) is played through in the real game with the real input before it
  counts as done; tests never assert a stand-in as the expected result, and a shipped gap is reported to the maintainer.
- Captures drive the game's real path and switch off the real devices' input.

### Process on a shared machine

- Cap load tests, stop processes by PID, time out long commands, and warn neighbouring projects first.

### First use

- Load and draw every enemy, weapon, effect and light state once behind a loading screen; keep the materials of
  short-lived effects alive.
- A browser run with a fresh profile that counts programs linked after the loading screen is the gate (zero).

### Hosting

- A playable web build is live from the first playable night and redeploys on merge.
- Before an online feature is called playable, walk the flow a stranger takes in the browser and in Discord: rooms, an
  invite link or a code, never a server address or `localhost` on a player-facing screen.
