# A length guard silently dropped every valid packet

2026-11-01

- **Saw:** the client connected and received snapshots but never became a player.
- **Cause:** the decoder's minimum-length check for the 8-byte welcome packet said 9, so a guard that fails closed
  discarded every valid welcome without a message.
- **Fix:** derive each minimum length from the layout comment, and count dropped packets while developing.
- **Docs:** [Multiplayer](../godot/multiplayer.md#godots-raw-websocket-without-the-high-level-multiplayer).
