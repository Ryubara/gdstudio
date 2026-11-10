# godot: Add a reload and ammo pickups

## Summary

Fixes #912. The weapon gets a reserve and a reload, ammo boxes the player walks over refill the reserve, the server
decides every shot a client asks for, and the weapon writes its ammo to the labels in the group `ammo_label`.

Read first: engines/godot/test-speed.md#time-driven-values

## Screenshots

Screenshots: none (nothing visible changed)

## Testing

- Weapon suite: 4 tests, all pass headless.
- Played a few rounds in the editor.

## Docs

Docs: none (no docs needed)

## Issues affected

None (no other issue is touched)

## Model

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>
