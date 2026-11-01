# Node 24 type stripping rejects parameter properties

2026-11-01

- **Saw:** TypeScript that type-checked crashed at start under Node 24 with a syntax error in a class constructor.
- **Cause:** Node runs TypeScript by stripping types only; constructor parameter properties, enums and namespaces need
  code generation.
- **Fix:** turn on `erasableSyntaxOnly` in `tsconfig.json` so `tsc` refuses them; write plain fields.
- **Docs:** Deadnight `docs/research/platform-backend.md`.
