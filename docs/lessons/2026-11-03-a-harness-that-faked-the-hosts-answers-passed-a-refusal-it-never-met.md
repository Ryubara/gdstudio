---
areas: [net, web, backend, tests]
---
# A harness that faked the host's answers passed, and the real host refused with 4006

2026-11-03

- **Saw:** after the first fix of Share in Discord (Deadnight #627) the maintainer pressed it in the real Activity and
  the new probe line read `refused after 17 ms; error rpc 4006: Not authenticated or invalid scope`, and the invite
  window failed with the same words. "Discord invites not working, needs research into how discord invites work, we
  might be missing some sort of scope." The first fix had passed every mode of its browser harness.
- **Cause:** the bridge called `authorize` (the sign-in code) and never `authenticate` (the access token that makes the
  Activity's session authenticated); Discord's client refuses `shareLink` and `openInviteDialog` with 4006 until it has.
  The first fix missed it for three reasons. Its harness replaced `discord-bridge.js` with a stub and answered
  `shareLink` with what a client *can* answer (a window, a close, silence, an error), so the SDK's handshake and the
  host's precondition were never in the run: a stand-in that accepts every command cannot find the one it refuses.
  The research read the reference's "No scopes required" as "nothing is needed first", but that line is about OAuth
  scopes, not about the session (the documented flow is `authorize`, the server's code exchange, then `authenticate`).
  And the backend had returned the `access_token` "for authenticate()" since the sign-in was written, which nothing used:
  a value that is returned for a purpose is a lead to check the purpose is served.
- **Fix:** Deadnight #627: the game hands the sign-in's `access_token` to the bridge, which runs `authenticate` before
  any command and makes a quick share wait for it; the lobby says the Activity is not signed in on a 4006 with no
  sign-in. The harness runs the real bridge with the real SDK in the frame and a fake Discord client in the page around
  it that speaks the SDK's frames and refuses every command with 4006 until `authenticate` ran
  (`activity.py --share --real-bridge --host-mode strict|reject-token|refuse-authorize`): against the old bridge it
  prints the maintainer's own line, against the new one the share goes through.
- **Check:** when a feature talks to a host we do not run (Discord, a browser permission, a payment API), the harness
  runs the shipped client code against a stand-in that enforces the host's documented preconditions (sign in first,
  scopes, order of calls), not one that answers each command as if the setup were done; it must fail with the real
  report's own words on the old code. A reference's "no scopes required" is read with the flow around it (what must be
  true before the call), and every value a backend returns "for the client" is traced to its use. A user's first real
  report is expected: ship the probe line that quotes the host's answer (the first fix did, and it found this in one
  press), and say in the PR what the stand-in models and what only the host can confirm.
- **Docs:** Deadnight `docs/research/web-export.md`, "Share in Discord: the Activity must authenticate (#627)".
