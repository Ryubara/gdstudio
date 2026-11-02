# The web build and the game server deployed minutes apart, and players were refused in between

2026-11-02

- **Saw:** after a protocol bump, players were refused for minutes; the live web build was a newer commit than the
  game server (web 00912e1 against server e4c5a6b; web went 79d9ff5, c67d81b, 08f1049 while the server lagged).
- **Cause:** the web build and the game server are separate Railway services that deploy on their own, minutes apart
  and in either order.
- **Fix:** before any live check, read `railway deployment list --service web --json` and the same for the server, and
  wait for the same commit with nothing building. A protocol bump lands server first, or the server accepts the
  previous version for one deploy.
- **Also:** `railway delete` deletes the whole project; a service is `railway service delete -s <name> -y`. Run
  `railway` from a scratch folder linked with `railway link -p <project> -e production`, never from a game checkout.
- **Docs:** [Railway CLI for a throwaway service](2026-11-01-railway-cli-for-a-throwaway-test-service.md),
  [Multiplayer](../godot/multiplayer.md).
