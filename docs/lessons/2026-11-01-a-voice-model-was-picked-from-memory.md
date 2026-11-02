---
areas: [audio, blender]
---
# The voice samples used a model picked from memory

2026-11-01

- **Saw:** the first soldier voice samples were made on ElevenLabs `eleven_v3`, while the account offered `eleven_v4`
  ("most emotive"); the maintainer asked "Are we using the best available model?" (Deadnight #384).
- **Cause:** the model name came from memory of an earlier session, and nobody listed what the vendor offered now.
  Vendors ship new models faster than an agent's notes.
- **Fix:** before generating with a vendor API, list its current models (`GET /v1/models`), pick from that list, and
  say in the pull request which model and why.
- **Docs:** [What the maintainer caught](../research/maintainer-corrections.md).
