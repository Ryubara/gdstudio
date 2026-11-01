# Fastify returned 400 instead of 401

2026-11-01

- **Saw:** a request with no session and an empty JSON body got 400, not 401.
- **Cause:** Fastify validates the body before `preHandler` hooks run, so an auth check there comes too late.
- **Fix:** authenticate in an `onRequest` hook, which runs before parsing and validation.
- **Docs:** Deadnight `docs/research/platform-backend.md`.
