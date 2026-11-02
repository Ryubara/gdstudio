# The menu could not tell a software renderer from a real GPU in the browser

2026-11-02

- **Saw:** the live 3D main menu (Deadnight #466) needed to fall back to a still stage on software rendering, but
  the adapter name Godot reports in a web export does not name the renderer.
- **Cause:** browsers mask the GPU adapter from the page by default; Godot's web build sees the masked string.
- **Fix:** read the unmasked renderer from WebGL (`WEBGL_debug_renderer_info`, `UNMASKED_RENDERER_WEBGL`) through
  `JavaScriptBridge`, and drop to the still stage when it names SwiftShader or another software renderer.
- **Docs:** [Web export](../godot/web-export.md).
