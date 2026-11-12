class_name SkinBuffers
extends RefCounted
## Has a browser on Direct3D 11 draw skinned meshes straight from the buffers the engine skins
## them into, instead of copying them out of the GPU at every draw.
##
## The Compatibility renderer skins a mesh on the GPU into a buffer of the `MeshInstance3D`'s own,
## made empty with `GL_DYNAMIC_DRAW`. ANGLE's Direct3D 11 backend (Chrome, Edge and Firefox on
## Windows) never binds a buffer of that hint to a draw: it copies the attributes out at every draw
## (a read back from the GPU, since the GPU wrote them), until 3 times the buffer's size has been
## copied with no write between, which a body skinned every frame never reaches. A skinned body then
## cost 0.10 to 0.25 ms a frame where it costs 0.06, at random per buffer and page (kit #1260,
## `docs/tools/blender/prototype-mannequins.md#browser-cost`).
##
## `PAGE_SCRIPT` wraps the page's `bufferData` before the engine boots: an array buffer made empty
## with `GL_DYNAMIC_DRAW` (the engine makes only its skinned and blend shape outputs and one small
## 2D buffer so) is made with `GL_STATIC_DRAW`, on a Direct3D renderer only. The hint is only a hint
## in GL: the engine writes the buffer as before and ANGLE binds it. With the `gds_game` editor
## plugin on, a web export writes it into `index.html`'s head (`SkinBuffersExport`). The page counts
## the buffers in `window.gdsSkinBuffers`; `window.gdsSkinBuffersOff = true` set before the engine
## boots (a probe measuring the engine's own hint) turns it off.

## Marks the script in a page, so a second export pass writes it once.
const PAGE_MARK := "window.gdsSkinBuffers = 0;"
## GL enums the script compares (`ARRAY_BUFFER`, `DYNAMIC_DRAW`, `STATIC_DRAW`).
const PAGE_SCRIPT := """
(() => {
  if (window.gdsSkinBuffers !== undefined || !window.WebGL2RenderingContext) { return; }
  window.gdsSkinBuffers = 0;
  const proto = WebGL2RenderingContext.prototype;
  const bufferData = proto.bufferData;
  const direct3d = (gl) => {
    if (gl.__gdsDirect3d === undefined) {
      const info = gl.getExtension('WEBGL_debug_renderer_info');
      const name = info ? String(gl.getParameter(info.UNMASKED_RENDERER_WEBGL)) : '';
      gl.__gdsDirect3d = name.indexOf('Direct3D') >= 0;
    }
    return gl.__gdsDirect3d;
  };
  proto.bufferData = function (target, size, usage, ...rest) {
    if (target === 0x8892 && usage === 0x88E8 && typeof size === 'number'
        && !window.gdsSkinBuffersOff && direct3d(this)) {
      usage = 0x88E4;
      window.gdsSkinBuffers++;
    }
    return bufferData.call(this, target, size, usage, ...rest);
  };
})();
"""


## `html` with the script in its head, before anything the head runs; as it was when it has no
## head or already has the script.
static func with_page_script(html: String) -> String:
	var head := html.find("<head>")
	if head < 0 or html.contains(PAGE_MARK):
		return html
	return html.insert(head + "<head>".length(), "\n<script>%s</script>" % PAGE_SCRIPT)
