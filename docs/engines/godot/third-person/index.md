# 3D Third Person pages

<!-- new section: split out of the third-person template page when it reached the size limit (#983) -->

The subpages of [the 3D Third Person template](../third-person-template.md), split by subject (#983). Put a new section
on the page of its subject, with an `{#anchor}`. A page is split at about 40 KB, before the 50 KB the check refuses
([Page size](../../../studio/rules.md#size)).

- [The character and its model](character.md): the animation libraries, the mannequins, replacing the model, the
  controller, the ragdoll and touch controls.
- [Prone and sliding](moves.md): lying down, the crawl and the slide.
- [Using things](interact.md): the `Interactable` component, the `Interactor` and the door's.
- [The character's clips](clips.md): the animation libraries and the template's own vault clips, with their checks.
- [Crouch, aim and shoot](shooting.md): the weapon, the bullet impacts and the effects.
- [The camera, the map and the screen](camera-and-ui.md): the follow camera, the map components, the minimap and the HUD.
- [AI characters](ai.md): the `AiCharacter` base, its `AiProfile`, the `AiDirector`'s thinks, tiers and budget, and
  the situation machine.
- [Vaulting and mantling](traversal.md): the `Vaultable` component, the probe, the warped path, the defaults and where
  they come from, and the level designer's how-to.
- [The game server](game-server.md): the headless server that admits and steps the players, its log and its cost.
- [The online client](online-client.md): the predicting client, the reconciler and stall guard, the puppets of the
  other players, and what it costs.
- [The online client over a bad network](online-gate.md): the bad-network gate, its thresholds, and how to run
  it natively and in the browser.
- [Shots, hits and deaths online](online-shots.md): who decides a hit, the events of a shot, a hit and a death, and
  what each screen makes itself.
- [Networked map parts](net-world.md): doors, platforms and pickups the server owns, met at the command's tick on both
  sides, and the checklist of a network-ready component.

What is in the template, the scene map and the route for a clip stay on [the template page](../third-person-template.md).
