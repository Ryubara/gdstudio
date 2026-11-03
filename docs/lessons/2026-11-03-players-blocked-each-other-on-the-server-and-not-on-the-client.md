---
areas: [net, tests]
---
# Players blocked each other on the server and not on the client, and the soak failed again after the crane fix

2026-11-03

- **Saw:** the bots-slots soak failed on `main` again, hours after the crane fix: "client 4 is 2.51 m from the server"
  (Deadnight #760). The gaps always sit just over the reconciler's 2.5 m snap, and the reconciler's own worst error
  was only 0.65 m, so it never saw the drift it was hiding. A trace showed the server body sliding along a parked car
  while the client body, 0.7 m off to one side, was pinned against the car's other face.
- **Cause:** every played body was on physics layer 1 and masked layers 1 and 2, so the server's bodies (people and
  bots, up to eight) stopped each other. The client draws the others as puppets with no collision. A sprint into a
  teammate or a bot stopped the server's body and not the client's; the 0.6 to 0.9 m that left grew into metres at the
  next corner of a car or a wall, and a correction that cannot move a blocked body hides the rest.
- **Fix:** a body sits on its own layer (4), which no body's mask lists, so bodies never block one another on either
  side. `test_world_parity.gd` walks one server body into another (it stopped at 0.8 m before, 8 m now), checks the
  layers, and the soak compares both worlds' solid things every 300 ticks and says in its failure line what each body
  slid on.
- **Note:** [the bots' spreading lesson](2026-11-02-bots-in-a-crowd-block-each-other-because-players-are-solid.md)
  worked around this solidity for bots alone; with bodies passing through each other that jam cannot happen.
- **Rays:** a ray that has to meet a body (a shot, the dead's swing, a grenade, footsteps, a ping) lists `PhysicsLayers.BODY`
  in its own mask; moving the layer alone made the dead's swing check stop meeting the bot and broke
  `test_smallmap_bot_night`, the first thing to fail when a ray is forgotten.
- **Docs:** [Multiplayer: same solid things](../godot/multiplayer.md#the-two-worlds-must-hold-the-same-solid-things).
  Check: a body the server blocks on something the client does not draw (or does not collide with) is a drift in
  waiting; list every way two server bodies can touch and make the client agree or the server ignore it.
