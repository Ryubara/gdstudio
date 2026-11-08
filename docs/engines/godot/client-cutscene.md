# A cutscene one client plays over a night the server runs

What Deadnight's helicopter drop (#1057: every player arrives by rope from a helicopter, on their own screen, at the
start of a night and on every late join) taught about showing something to one player while the night goes on for
everyone. The game's own page is its `docs/design/arrival.md`; this one is for the next cutscene of this kind.

## Who owns what

| Owner | What it holds | Why |
| --- | --- | --- |
| The client | every node of the show (camera, models, light, sounds, black bars), built when it begins and freed when it ends | the others must see nothing, and a player who never meets it pays nothing |
| The server | the **shield**: for as long as the show plays, the player cannot be hurt, is not chased, takes no part in the night and is not drawn by the others | the body is in the world from the moment of joining and the dead do not know about a screen |
| The wire | one small message, begin and end (two bytes) | the server has to be told; it must never wait for it |

## The server's half

- **The client's word starts and ends the shield, a cap ends it too.** A client that stalls, closes or lies is shielded
  no longer than the cap (`cap_seconds`); a skip or a slow web build is followed by the client's end message, not a
  guessed timer, so neither is a free invulnerability nor a hurt. Add a short **grace** after the end, in which the
  player has the controls and a blow still does nothing.
- **Put the shield where every effect passes.** Every blow (a zombie's, a grenade's, the ray gun's splash) reaches the
  rules through one action, so the rules refuse it there; the places that *choose* targets (who the dead chase) and
  that *read commands* (movement, shots, use) check the same state, so nothing walks up to a body nobody sees and a
  modified client cannot walk off invulnerable. The state rides the rules' snapshot (a late joiner and a resumed client
  read it) and the frame (a flag the others draw by).
- **One a seat, and only when asked.** The server grants a shield only on the message, once for the seat, not to a bot,
  not to a client that resumes its seat, so a client that never sends it (a bot, a test client) is never shielded and
  every older suite runs as it did.
- **Bump the protocol version** for a new message type, give it a size and a rate in the peer limits, and let a wrong
  size or value be a strike.
- **Other clients draw nothing of the player until it ends**: hide the avatar, skip its name marker, and let the bots'
  beliefs leave it out.

## The client's half

- **Take the picture, not the input.** Keep the player's mouse grip as it is (a browser gives a pointer lock only to a
  click: letting go for the show may lose it for good), lock the mouse look, send neutral commands and hide the body;
  give the HUD, the reticle and the touch layer back when the show ends. The pause menu still works.
- **Stand the camera where nothing solid is between it and the spot.** A fixed offset put Deadnight's camera behind the
  lot's movie screen. Try headings round the spot, nearest the preferred one first, casting a ray for each line the
  show needs (camera to spot, spot to the sky the helicopter hangs in, camera to what it looks at), and take the first
  clear one. A map with a roof over the spot hides the roof for the show and its rays ignore the roof's bodies.
- **Frame what must be in the picture, then come in.** A camera that shows the whole drop (ground to rotor top) shows
  the Soldier at 25 px; ease it in toward the player as they land.
- **A function of time, not a state machine.** One pure class returns every position for a moment `t` (camera,
  helicopter, rope, light, fade, sound level); the node only places them. A test reads any moment, the show steps in
  the physics step so a Movie Maker capture and a test see the same show, and it can be tuned without touching the node.
- **Fake what the engine charges for.** The Compatibility renderer lights each mesh once for each light in reach: the
  lamp is one unshadowed `SpotLight3D` and its beam an additive cone on the game's haze shader (one draw), the helicopter's
  paint glows a little with its own colour instead of taking a light.
- **Load only when it plays.** A sound bank marked `on_demand` is skipped by the night's loading bar and the background
  decode; the show loads its three sounds and its model at the black it starts from.
- **Off unless asked.** The show is a person's (`night.arrival = true` set by the screen), never a test's, a bot's or
  a headless run's. A page that asks for the probes skips it unless the page asks for the show too (a bridge call the
  page makes anyway), so the dozens of web probes that drive a night from its first frame need no edit.

## Measuring it

An elevated camera sees far more of the lot than the player's own does: Deadnight's show draws about 240 calls where the
player's view draws 30 to 50 (the engine's count), and in a browser about 450 where the night after draws about 110.
Count it as the web docs say (WebGL calls in each page frame, `smoke.trace`), ablate the light, and check the objects
and nodes return to where they started. See [Performance budgets](performance-budgets.md) and
[the web export](web-export.md).
